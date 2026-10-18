"""Generate exact aligned biome/height masks and auditable planning artifacts.

Requires Python 3.10+, numpy and Pillow. No Godot resources or source art are edited.
Polygons use normalized map-boundary coordinates; reservations retain physical size.
"""
from __future__ import annotations

import argparse
from collections import Counter, deque
import csv
import hashlib
import heapq
import json
import math
from pathlib import Path
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont, PngImagePlugin


GENERATOR = "generate_world_map_template.py/v1"
ROOT = Path(__file__).resolve().parents[1]
NEIGHBORS = ((1, 0), (0, 1), (-1, 0), (0, -1))
DELIVERY_FILES = (".gdignore", "biome_mask.png", "height_map.png", "map_preview.png",
                  "biome_preview.png", "height_preview.png", "generation_config.json",
                  "planning_markers.json", "planning_markers.csv", "connections.json",
                  "routes.json", "validation_report.json", "map_notes.md")


def checked_output(path):
    """Honor the user's private workspace boundary, including symlink resolution."""
    resolved = Path(path).resolve()
    if not resolved.is_relative_to(ROOT) or resolved == ROOT:
        raise ValueError(f"Output must be a subdirectory of the private workspace: {ROOT}")
    archive = resolved.with_suffix(".zip")
    if not archive.resolve().is_relative_to(ROOT):
        raise ValueError("Archive path leaves the private workspace")
    if resolved.exists():
        for name in (*DELIVERY_FILES, "map_metadata.json"):
            if not (resolved/name).resolve().is_relative_to(ROOT):
                raise ValueError(f"Output file redirects outside the private workspace: {name}")
    return resolved


def save_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def smooth_polygon(points, passes):
    points = np.array(points, dtype=float)
    for _ in range(passes):
        following = np.roll(points, -1, axis=0)
        points = np.stack((.75 * points + .25 * following,
                           .25 * points + .75 * following), axis=1).reshape(-1, 2)
    return points


def polygon_mask(points, shape, passes):
    """Sample at cell centers, via vectorized even/odd ray crossing (no antialias)."""
    h, w = shape
    x = (np.arange(w)[None, :] + .5) / w
    z = (np.arange(h)[:, None] + .5) / h
    inside = np.zeros(shape, dtype=bool)
    vertices = smooth_polygon(points, passes)
    for a, b in zip(vertices, np.roll(vertices, -1, axis=0)):
        if a[1] == b[1]:
            continue
        crosses = (a[1] > z) != (b[1] > z)
        crossing_x = (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1]) + a[0]
        inside ^= crosses & (x < crossing_x)
    return inside


def components(mask):
    unseen = mask.copy()
    sizes = []
    h, w = mask.shape
    for z, x in zip(*np.nonzero(mask)):
        if not unseen[z, x]:
            continue
        queue = deque([(x, z)])
        unseen[z, x] = False
        size = 0
        while queue:
            xx, zz = queue.popleft()
            size += 1
            for dx, dz in NEIGHBORS:
                nx, nz = xx + dx, zz + dz
                if 0 <= nx < w and 0 <= nz < h and unseen[nz, nx]:
                    unseen[nz, nx] = False
                    queue.append((nx, nz))
        sizes.append(size)
    return sorted(sizes, reverse=True)


def inset_walkable(mask, width_cells):
    """Conservative square clearance; every route center has a full-width square."""
    before = width_cells // 2
    after = width_cells - before
    padded = np.pad(mask.astype(np.int64), ((before, after), (before, after)))
    summed = np.pad(padded, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    h, w = mask.shape
    k = width_cells
    totals = (summed[k:k+h, k:k+w] - summed[:h, k:k+w]
              - summed[k:k+h, :w] + summed[:h, :w])
    return totals == k * k


def astar(mask, start, end):
    h, w = mask.shape
    start, end = tuple(start), tuple(end)
    if not mask[start[1], start[0]] or not mask[end[1], end[0]]:
        raise ValueError(f"Route endpoint lacks clearance: {start} -> {end}")
    queue = [(0, 0, start)]
    costs, parents = {start: 0}, {start: None}
    while queue:
        _, cost, cur = heapq.heappop(queue)
        if cost != costs[cur]:
            continue
        if cur == end:
            path = []
            while cur is not None:
                path.append(list(cur))
                cur = parents[cur]
            return path[::-1]
        for dx, dz in NEIGHBORS:
            nx, nz = cur[0] + dx, cur[1] + dz
            nxt = (nx, nz)
            if 0 <= nx < w and 0 <= nz < h and mask[nz, nx]:
                new_cost = cost + 1
                if new_cost < costs.get(nxt, math.inf):
                    costs[nxt], parents[nxt] = new_cost, cur
                    heuristic = abs(nx - end[0]) + abs(nz - end[1])
                    heapq.heappush(queue, (new_cost + heuristic, new_cost, nxt))
    raise ValueError(f"No baseline route: {start} -> {end}")


def generate(config, output):
    output = checked_output(output)
    cell = config["cell_size_m"]
    size = config["world_size_m"]
    if cell != 2 or any(v % cell or not 0 < v <= 1200 for v in size):
        raise ValueError("World dimensions must be multiples of 2m, each <=1200m.")
    w, h = [int(v // cell) for v in size]
    origin = [-size[0] / 2, -size[1] / 2]
    base_y = config["baseline_world_y_m"]
    if base_y < 4 or base_y % 2:
        raise ValueError("Baseline must be an even Y >=4m to accommodate the waterbed.")
    passes = config["polygon_smoothing_passes"]
    biomes = np.zeros((h, w), dtype=np.uint8)
    for polygon in config["biome_polygons_normalized"]:
        biomes[polygon_mask(polygon["points"], (h, w), passes)] = polygon["biome_id"]
    heights = np.zeros((h, w), dtype=np.int16)
    for plateau in config["plateaus"]:
        region = polygon_mask(plateau["points"], (h, w), passes)
        heights[region & (biomes == plateau["biome_id"])] = plateau["relative_m"]
    heights[biomes == 3] = -2

    def world_point(p):
        x, z = p
        return [origin[0] + (x + .5) * cell,
                base_y + int(heights[z, x]), origin[1] + (z + .5) * cell]

    def rectangle_record(rect):
        rect = [int(v) for v in rect]
        x, z, rw, rh = rect
        return {"cell_rect_x_z_width_depth": rect,
                "world_min_xz_m": [origin[0] + x * cell, origin[1] + z * cell],
                "size_m": [rw * cell, rh * cell]}

    def rect_cells(rect):
        x, z, rw, rh = rect
        if x < 0 or z < 0 or x + rw > w or z + rh > h:
            raise ValueError(f"Reservation outside map: {rect}")
        return np.s_[z:z+rh, x:x+rw]

    def make_point(record, default_biome=0):
        x, z = [min(d - 1, int(v * d)) for v, d in
                zip(record["center_normalized"], (w, h))]
        rw, rh = [int(v // cell) for v in record["reservation_size_m"]]
        rect = [x - rw // 2, z - rh // 2, rw, rh]
        region = rect_cells(rect)
        assert np.all(heights[region] == 0), (record["id"], "point reservation not flat")
        assert np.all(biomes[region] == record.get("biome_id", default_biome)), record["id"]
        return {**record, "cell_xz": [x, z], "world_xyz_m": world_point((x, z)),
                "reservation": rectangle_record(rect), "status": "planning_candidate"}

    def make_site(record):
        rw, rh = [int(v // cell) for v in record["size_m"]]
        margin = int(record["margin_m"] // cell)
        cx, cz = [int(v * d) for v, d in zip(record["center_normalized"], (w, h))]
        rect = [cx - rw // 2, cz - rh // 2, rw, rh]
        x, z, _, _ = rect
        outer = [x-margin, z-margin, rw+2*margin, rh+2*margin]
        region = rect_cells(outer)
        assert np.all(heights[region] == 0), (record["id"], "site plus margin not flat")
        assert np.all(biomes[region] == record["biome_id"]), (record["id"], "biome mismatch")
        side = record["entrance_side"]
        # Entrance coordinates are clear staging pads outside the actual footprint.
        # Keep the 8m route width clear even at the final center point.
        half_width = math.ceil(config["route_width_m"] / cell / 2)
        door = {"north": [cx, z-half_width-1], "south": [cx, z+rh+half_width],
                "west": [x-half_width-1, cz], "east": [x+rw+half_width, cz]}[side]
        approach = {"north": [cx, z-margin-half_width-1], "south": [cx, z+rh+margin+half_width],
                    "west": [x-margin-half_width-1, cz], "east": [x+rw+margin+half_width, cz]}[side]
        geometric_center = [origin[0]+(x+rw/2)*cell, base_y,
                            origin[1]+(z+rh/2)*cell]
        return {**record, "footprint": rectangle_record(rect),
                "reservation_with_margin": rectangle_record(outer),
                "center_cell_xz": [cx, cz], "center_world_xyz_m": geometric_center,
                "center_cell_meaning": "representative_cell_index; world_center_is_exact_geometric_center_of_rectangle",
                "entrance_cell_xz": door, "entrance_world_xyz_m": world_point(door),
                "entrance_coordinate_meaning": "clear_staging_pad_outside_candidate_footprint_not_internal_prefab_door",
                "approach_cell_xz": approach, "approach_world_xyz_m": world_point(approach),
                "status": "planning_candidate_not_real_prefab_footprint"}

    spawn = make_point(config["spawn"])
    growth = [make_point(p) for p in config["growth_points"]]
    challenges = [make_site(s) for s in config["challenges"]]
    portal = make_site(config["portal"])
    sites = challenges + [portal]
    reservations = [(s["id"], s["reservation_with_margin"]["cell_rect_x_z_width_depth"]) for s in sites]
    reservations += [(p["id"], p["reservation"]["cell_rect_x_z_width_depth"]) for p in [spawn] + growth]
    for i, (aid, (ax, az, aw, ah)) in enumerate(reservations):
        for bid, (bx, bz, bw, bh) in reservations[i+1:]:
            assert not (ax < bx+bw and bx < ax+aw and az < bz+bh and bz < az+ah), (aid, bid, "overlap")

    baseline = (biomes != 3) & (heights == 0)
    # A site is treated as an opaque obstacle; no path can cross an unfinished challenge.
    outside = baseline.copy()
    for site in sites:
        outside[rect_cells(site["reservation_with_margin"]["cell_rect_x_z_width_depth"])] = False
    clearance = inset_walkable(outside, int(config["route_width_m"] // cell))
    route_targets = [(p["id"], p["cell_xz"]) for p in growth]
    route_targets += [(s["id"], s["approach_cell_xz"]) for s in sites]
    routes = []
    for target_id, target in route_targets:
        path = astar(clearance, spawn["cell_xz"], target)
        site = next((s for s in sites if s["id"] == target_id), None)
        if site:
            # Continue inside only this site's reserved apron, ending outside its footprint.
            apron = baseline.copy()
            for other in sites:
                field = "footprint" if other is site else "reservation_with_margin"
                apron[rect_cells(other[field]["cell_rect_x_z_width_depth"])] = False
            segment = astar(inset_walkable(apron, int(config["route_width_m"] // cell)),
                            target, site["entrance_cell_xz"])
            path.extend(segment[1:])
        routes.append({"id": f"S1_to_{target_id}", "from": spawn["id"], "to": target_id,
                       "cells_xz": path, "world_polyline_xyz_m": [world_point(p) for p in path],
                       "length_m": (len(path)-1)*cell, "guaranteed_clear_width_m": config["route_width_m"],
                       "height_changes": 0, "connections_used": [],
                       "status": "verified_on_2d_grid_only"})

    # For reporting exploration detours, measure each growth space -> portal entrance as well.
    portal_route = next(r for r in routes if r["to"] == portal["id"])
    for p in growth:
        route = astar(clearance, p["cell_xz"], portal["approach_cell_xz"])
        apron = baseline.copy()
        for other in sites:
            field = "footprint" if other is portal else "reservation_with_margin"
            apron[rect_cells(other[field]["cell_rect_x_z_width_depth"])] = False
        tail = astar(inset_walkable(apron, int(config["route_width_m"] // cell)),
                     portal["approach_cell_xz"], portal["entrance_cell_xz"])
        route.extend(tail[1:])
        routes.append({"id": f"{p['id']}_to_P1", "from": p["id"], "to": "P1",
                       "cells_xz": route, "world_polyline_xyz_m": [world_point(q) for q in route],
                       "length_m": (len(route)-1)*cell, "guaranteed_clear_width_m": config["route_width_m"],
                       "height_changes": 0, "connections_used": [], "status": "verified_on_2d_grid_only"})

    connections = []
    for request in config["planned_connections"]:
        width = int(request["width_m"] // cell)
        candidates = []
        tx, tz = [v * d for v, d in zip(request["near_normalized"], (w, h))]
        for z, x in zip(*np.nonzero((biomes == request["biome_id"]) & (heights == request["low_relative_m"]))):
            for dx, dz in NEIGHBORS:
                # Six parallel two-cell stairs, plus one landing cell at each end.
                px, pz = -dz, dx
                strips = [[(x + dx*k + px*j, z + dz*k + pz*j) for k in (-1, 0, 1, 2)]
                          for j in range(-(width//2), width-width//2)]
                if all(0 <= xx < w and 0 <= zz < h and biomes[zz, xx] == request["biome_id"]
                       and heights[zz, xx] == (request["low_relative_m"] if k < 2 else request["high_relative_m"])
                       for strip in strips for k, (xx, zz) in enumerate(strip)):
                    candidates.append(((x-tx)**2 + (z-tz)**2, int(x), int(z), dx, dz, strips))
        assert candidates, (request["id"], "no full-width connection footprint")
        _, x, z, dx, dz, strips = min(candidates)
        all_cells = [p for strip in strips for p in strip]
        minx, minz = min(q[0] for q in all_cells), min(q[1] for q in all_cells)
        maxx, maxz = max(q[0] for q in all_cells), max(q[1] for q in all_cells)
        lows = [strip[1] for strip in strips]
        highs = [strip[2] for strip in strips]
        def endpoint(points, side):
            positions = np.array([world_point(p) for p in points])
            center = positions.mean(axis=0)
            center += np.array([dx * cell/2 * side, 0, dz * cell/2 * side])
            return center.tolist()
        connections.append({**request, "type": "stair_bank", "rise_m": 2,
                            "stair_run_m": 4, "landing_depth_each_m": 2,
                            "low_world_xyz_m": endpoint(lows, -1), "high_world_xyz_m": endpoint(highs, 1),
                            "endpoint_meaning": "outer_edges_of_two_cell_stair_run; landings_extend_2m_beyond_each_endpoint",
                            "footprint_with_landings": rectangle_record([minx,minz,maxx-minx+1,maxz-minz+1]),
                            "parallel_lanes": [{"low_cell_xz": [int(v) for v in lo], "high_cell_xz": [int(v) for v in hi]}
                                               for lo, hi in zip(lows, highs)],
                            "status": "planned_not_instantiated_or_physics_verified",
                            "counted_for_required_reachability": False})

    palette = np.array([b["rgb"] for b in config["biomes"]], dtype=np.uint8)
    rgb = palette[biomes]
    gray = np.zeros((h, w), dtype=np.uint8)
    for band in config["height_bands"]:
        gray[heights == band["relative_m"]] = band["gray"]
    output.mkdir(parents=True, exist_ok=True)
    # These are data-delivery PNGs and CSV, not texture or localization imports.
    (output / ".gdignore").write_text("", encoding="utf-8")
    save_json(output / "map_metadata.json", {"generator": GENERATOR, "status": "generating"})
    pnginfo = PngImagePlugin.PngInfo()
    pnginfo.add_text("purpose", "exact data mask; no display overlays; linear integer values")
    Image.fromarray(rgb).save(output / "biome_mask.png", pnginfo=pnginfo)
    Image.fromarray(gray).save(output / "height_map.png", pnginfo=pnginfo)
    # Read the serialized masks back: the delivered PNGs, not only in-memory arrays, are audited.
    with Image.open(output / "biome_mask.png") as im:
        assert im.mode == "RGB" and im.size == (w, h)
        decoded_biome = np.array(im)
    with Image.open(output / "height_map.png") as im:
        assert im.mode == "L" and im.size == (w, h)
        decoded_height = np.array(im)
    assert np.array_equal(decoded_biome, rgb) and np.array_equal(decoded_height, gray)
    assert {tuple(c) for c in decoded_biome.reshape(-1, 3)} == {tuple(b["rgb"]) for b in config["biomes"]}
    assert set(np.unique(decoded_height)) == {b["gray"] for b in config["height_bands"]}
    counts = Counter(biomes.ravel().tolist())
    biome_stats = []
    for b in config["biomes"]:
        sizes = components(biomes == b["id"])
        assert len(sizes) == 1, (b["key"], sizes, "fragmented biome")
        biome_stats.append({**b, "hex": "#" + "".join(f"{v:02X}" for v in b["rgb"]),
                            "cells": counts[b["id"]], "area_m2": counts[b["id"]] * cell**2,
                            "area_percent": round(counts[b["id"]] / (w*h) * 100, 3),
                            "connected_components_4way": len(sizes)})
    baseline_components = components(baseline)
    assert len(baseline_components) == 1, "Lowland land is disconnected"
    dry = biomes != 3
    cliff_jumps = []
    for axis in (0, 1):
        jump = np.abs(np.diff(heights, axis=axis))
        mask = np.take(dry, range(dry.shape[axis]-1), axis=axis) & np.take(dry, range(1,dry.shape[axis]), axis=axis)
        cliff_jumps.append(int(jump[mask].max(initial=0)))
    assert max(cliff_jumps) <= 2, "Unintended 4m cliff skips terrace"
    water_y = config["water_surface_world_y_m"]
    assert base_y - 2 < water_y < base_y
    checks = {"png_dimensions_and_modes": "pass", "png_roundtrip_exact": True,
              "undefined_biome_pixels": 0, "undefined_height_pixels": 0,
              "biome_components": {b["key"]: b["connected_components_4way"] for b in biome_stats},
              "baseline_land_components_4way": len(baseline_components),
              "baseline_land_area_percent_of_dry_land": round(int(baseline.sum()) / int(dry.sum()) * 100, 3),
              "land_height_components": {str(v): components(dry & (heights == v)) for v in (0, 2, 4)},
              "max_unconnected_adjacent_dry_height_difference_m": max(cliff_jumps),
              "all_site_footprints_and_full_margins_flat_and_allowed_biome": True,
              "all_planning_reservations_nonoverlapping": True,
              "route_count": len(routes), "route_clear_width_m": config["route_width_m"],
              "water_and_all_cross_layer_edges_excluded_from_routes": True,
              "other_site_full_margin_reservations_excluded_from_routes": True,
              "checked_spawn_portal_combinations": [[spawn["id"], portal["id"]]],
              "planned_connections_not_used_in_reachability": True,
              "real_prefab_footprint_rotation_tags_collision_and_3d_seams": "not_tested_no_real_prefabs",
              "physics_or_navigation_or_gui_acceptance": "not_tested_no_3d_map_generated"}
    save_json(output / "generation_config.json", config)
    save_json(output / "planning_markers.json", {"status": "candidates_only", "spawn": spawn,
                                                "growth_spaces": growth, "challenges": challenges, "portal": portal})
    save_json(output / "connections.json", {"connections": connections})
    save_json(output / "routes.json", {"movement": "four_neighbors_same_height_dry_only",
                                       "actual_roads_painted": False, "routes": routes})
    save_json(output / "validation_report.json", checks)
    with (output / "planning_markers.csv").open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "type", "cell_x", "cell_z", "world_x_m", "world_y_m", "world_z_m", "width_m", "depth_m"])
        for kind, values in (("spawn", [spawn]), ("growth_space", growth), ("challenge", challenges), ("portal", [portal])):
            for value in values:
                p = value.get("cell_xz", value.get("center_cell_xz"))
                xyz = value.get("world_xyz_m", value.get("center_world_xyz_m"))
                dimensions = value.get("reservation_size_m", value.get("size_m"))
                writer.writerow([value["id"], kind, *p, *xyz, *dimensions])
    render_preview(output, config, biomes, heights, biome_stats, spawn, growth, sites, routes, connections)
    write_notes(output, config, biome_stats, checks, spawn, sites, routes, connections)
    files = [output/name for name in DELIVERY_FILES]
    metadata = {"schema_version": 1, "generator": GENERATOR, "template_id": config["template_id"],
                "design_date": "2026-10-18", "world_size_m": size, "pixel_size": [w,h],
                "meters_per_pixel": cell, "world_boundary_min_xz_m": origin,
                "world_boundary_max_xz_m": [origin[0]+size[0],origin[1]+size[1]],
                "axis_convention": {"right": "+X", "down": "+Z", "row_major": True,
                                    "pixel_zero_is": "minimum_xz_cell_not_world_origin",
                                    "pixel_center_formula": "X=minX+(u+0.5)*2; Z=minZ+(v+0.5)*2",
                                    "rectangles": "min-inclusive, max-exclusive; cell_xz=(column,row)"},
                "biome_encoding": {"file": "biome_mask.png", "mode": "RGB", "palette": biome_stats},
                "height_encoding": {"file": "height_map.png", "mode": "L", "baseline_world_y_m": base_y,
                                    "meaning": "solid_surface_top_including_submerged_bed_not_water_surface",
                                    "mapping": [{**b, "world_y_m": base_y+b["relative_m"],
                                                 "top_solid_layer_index": int((base_y+b["relative_m"])/2-1)}
                                                for b in config["height_bands"]],
                                    "godot_v8": "surface_y(L)=(L+1)*2; L=(baseline_Y+relative_height)/2-1",
                                    "proposal_for_solid_columns": "explicitly fill layers 0..L using layered APIs; no caves in this template"},
                "water": {"identification": "biome_id=3_only", "bed_relative_height_m": -2,
                          "bed_world_y_m": base_y-2, "surface_world_y_m": water_y,
                          "depth_m": water_y-(base_y-2), "shore_world_y_m": base_y,
                          "surface_is": "proposed_separate_plane_not_encoded_in_height_png",
                          "requires_future_import_adapter": True, "initially_walkable": False},
                "candidate_policy": {"challenge_count": "3_proposed_not_confirmed", "challenge_margin_m": 12,
                                     "spawn_count": 1, "portal_count": 1,
                                     "actual_prefab_masks_and_rotations": "not_available_revalidate_at_embedding"},
                "reproduction": {"configuration": "generation_config.json", "randomness": "none",
                                 "algorithm": "Chaikin_smoothed_normalized_polygons_cell_center_even_odd_sampling",
                                 "dependencies": {"numpy": np.__version__, "Pillow": Image.__version__},
                                 "command": "python tools/generate_world_map_template.py --config <generation_config.json> --output <new_directory>"},
                "files_sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
                "import_status": "data_delivery_only_no_png_to_LevelData_importer_added",
                "validation": checks}
    save_json(output / "map_metadata.json", metadata)
    print(json.dumps({"output": str(output), "biomes": biome_stats,
                      "routes_m": {r["id"]: r["length_m"] for r in routes}, "checks": checks}, ensure_ascii=False))


def font(size, bold=False):
    names = (["C:/Windows/Fonts/msyhbd.ttc"] if bold else ["C:/Windows/Fonts/msyh.ttc"])
    names += ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
    for name in names:
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default(size=size)


def render_preview(output, config, biomes, heights, stats, spawn, growth, sites, routes, connections):
    w, h = biomes.shape[1], biomes.shape[0]
    side = 850
    panel_w, panel_h = round(side * w / max(w,h)), round(side * h / max(w,h))
    canvas = Image.new("RGB", (1980, 1580), "#F3F1EA")
    d = ImageDraw.Draw(canvas)
    ink, muted = "#26343B", "#55646B"
    d.text((62,34), "聚光灯 / 畸变   大世界布局初稿", fill=ink, font=font(40,True))
    d.text((64,92), f"建议模板 v0.1   ·   {config['world_size_m'][0]} × {config['world_size_m'][1]} m   ·   2 m / 格   ·   同一模板地形固定", fill=muted, font=font(23))
    panels = [(74,195),(1058,195)]
    d.text((74,147), "01  生态与空间预留", fill=ink, font=font(28,True))
    d.text((1058,147), "02  相对高度与初始通行", fill=ink, font=font(28,True))
    palette = np.array([b["rgb"] for b in config["biomes"]], dtype=np.uint8)
    rgb = palette[biomes]
    hp = np.zeros_like(rgb)
    for level, color in ((-2,(62,121,152)),(0,(224,225,210)),(2,(178,154,118)),(4,(120,101,87))):
        hp[heights == level] = color
    for index, (px,pz) in enumerate(panels):
        image = Image.fromarray(rgb if index == 0 else hp).resize((panel_w,panel_h),Image.Resampling.NEAREST)
        canvas.paste(image,(px,pz))
        def xy(p):
            return (px+(p[0]+.5)*panel_w/w, pz+(p[1]+.5)*panel_h/h)
        # Light measurement grid is preview-only.
        for meters in range(0, int(config["world_size_m"][0])+1,100):
            xx = px+meters/config["world_size_m"][0]*panel_w
            d.line((xx,pz,xx,pz+panel_h), fill="#FFFFFF",width=1)
            d.text((xx-12,pz+panel_h+10),str(meters),fill=muted,font=font(16))
        for meters in range(0,int(config["world_size_m"][1])+1,100):
            zz = pz+meters/config["world_size_m"][1]*panel_h
            d.line((px,zz,px+panel_w,zz),fill="#FFFFFF",width=1)
            d.text((px-36,zz-9),str(meters),fill=muted,font=font(16))
        d.rectangle((px,pz,px+panel_w,pz+panel_h),outline="#51616A",width=2)
        d.text((px,pz+panel_h+38),"刻度为距左上角的米数；左上角世界坐标 (-W/2, -D/2)",fill=muted,font=font(17))
        for r in routes:
            if r["from"] != spawn["id"]:
                continue
            color = "#B73A66" if r["to"] == "P1" else "#FAF4D6"
            coords = [xy(p) for p in r["cells_xz"]]
            d.line(coords, fill="#48574D",width=7)
            d.line(coords, fill=color,width=4)
        for s in sites:
            def box(field):
                x,z,rw,rh = s[field]["cell_rect_x_z_width_depth"]
                return (px+x*panel_w/w,pz+z*panel_h/h,px+(x+rw)*panel_w/w,pz+(z+rh)*panel_h/h)
            outer = box("reservation_with_margin")
            inner = box("footprint")
            color = "#A72F64" if s["id"] == "P1" else "#243B42"
            # Corners distinguish the reserved blending apron from the inner content frame.
            for ax,az,sx,sz in ((outer[0],outer[1],1,1),(outer[2],outer[1],-1,1),
                              (outer[0],outer[3],1,-1),(outer[2],outer[3],-1,-1)):
                d.line((ax+sx*13,az,ax,az,ax,az+sz*13),fill=color,width=2)
            d.rectangle(inner,outline=color,width=4)
            label = f"{s['id']}  {'30×30m' if s['id']=='P1' else '100×100m'}"
            label_y = inner[1]+10 if s["id"] != "P1" else inner[3]+8
            bbox = d.textbbox((inner[0]+7,label_y),label,font=font(19,True))
            d.rectangle((bbox[0]-3,bbox[1]-3,bbox[2]+3,bbox[3]+3),fill="#F4F1E7")
            d.text((inner[0]+7,label_y),label,fill=color,font=font(19,True))
            ex,ez=xy(s["entrance_cell_xz"])
            d.ellipse((ex-5,ez-5,ex+5,ez+5),fill="#E45B35",outline="white",width=2)
        for p in [spawn]+growth:
            xx,zz=xy(p["cell_xz"])
            color="#A72F64" if p["id"] == spawn["id"] else "#256548"
            d.ellipse((xx-9,zz-9,xx+9,zz+9),fill=color,outline="white",width=3)
            d.text((xx+12,zz-16),p["id"],fill=ink,font=font(23,True),stroke_width=2,stroke_fill="#F3F1EA")
        for connection in connections:
            x,z,rw,rh=connection["footprint_with_landings"]["cell_rect_x_z_width_depth"]
            xx,zz=xy((x+rw/2-.5,z+rh/2-.5))
            d.rectangle((xx-9,zz-9,xx+9,zz+9),fill="#F3A238",outline="#663E0B",width=2)
            d.text((xx+13,zz-15),connection["id"]+"*",fill="#613C0E",font=font(21,True),stroke_width=2,stroke_fill="#F3F1EA")
    y=1150
    d.line((64,y-22,1915,y-22),fill="#C8CCC4",width=2)
    d.text((70,y),"生态面积 / 纯色数据",fill=ink,font=font(25,True))
    for i,b in enumerate(stats):
        yy=y+48+i*42
        d.rectangle((74,yy+4,99,yy+29),fill=tuple(b["rgb"]))
        d.text((112,yy),f"{b['name']}  {b['area_percent']:.1f}%   {b['hex']}",fill=ink,font=font(22))
    d.text((520,y),"高度 / 水位建议",fill=ink,font=font(25,True))
    rows=["陆地 0 / +2 / +4 m；灰度 85 / 170 / 255", "水底 -2 m；灰度 0；不代表空气",f"基准地面 Y={config['baseline_world_y_m']} m；水面 Y={config['water_surface_world_y_m']} m", "高台仅 3 块；无噪声碎台阶"]
    for i,row in enumerate(rows):
        d.text((520,y+48+i*42),row,fill=ink,font=font(21))
    d.text((1180,y),"通路 / 尺度检查",fill=ink,font=font(25,True))
    portal_route=next(r for r in routes if r["from"]=="S1" and r["to"]=="P1")
    for i,row in enumerate([f"S1 → P1：网格步行 {portal_route['length_m']} m", f"路线净宽 ≥ {config['route_width_m']} m；避开水面和所有跨层边", "候选挑战 3 处；各含 12 m 外围衔接", "* T1–T3 仅规划，未计入必要路线"]):
        d.text((1180,y+48+i*42),row,fill=ink,font=font(21))
    d.rounded_rectangle((64,1410,1915,1545),radius=12,fill="#E5E8DE")
    d.text((86,1426),"S1 出生候选   ·   G1–G3 成长空间   ·   C1–C3 挑战候选   ·   P1 传送门候选",fill=ink,font=font(23,True))
    d.text((86,1470),"框、点、路线仅用于策划检查；基础 PNG 不含标记。通行已做二维检查，预制嵌入、阶梯、水体与碰撞仍需三维验证。",fill=muted,font=font(21))
    canvas.save(output/"map_preview.png")
    for name, data in (("biome_preview.png",rgb),("height_preview.png",hp)):
        Image.fromarray(data).resize((w*3,h*3),Image.Resampling.NEAREST).save(output/name)


def write_notes(output, config, stats, checks, spawn, sites, routes, connections):
    text = f"""# 生态分布与高度布局初稿 v0.1

日期：2026-10-18。依据 `map_generation_brief.md` 与 `world_generation_and_run_flow.md`。
本次新增独立数据交付与 Python 生成工具，属于地图源数据准备；没有修改地形编辑器、运行时、美术规范或既有地图。

## 建议方案

中央与西南为连续草原，西北为岩地，东部为沙漠，东南为低地水域。
三种陆地均保留宽阔的基准平地，岩地并不全部升高。高差集中在西北 +2m 台地、其内 +4m 高台和东北沙漠 +2m 台地。
不使用随机噪声、碎岛、零散凸台或每局重分生态。四种生态各为一个四邻接连续区域。

本稿建议 1 个出生候选、1 个传送门候选、3 处 100×100m 挑战候选，各挑战外加 12m 衔接带（共 124×124m）。
传送门为 30×30m，外加 12m 衔接带（共 54×54m）。这些是建议预留，并非历史已确认数量或真实资源占地。
出生另示意 20×20m 预留，成长空间各 16×16m，路线净宽建议 8m；这些也只是本稿参数。
成长标记表示可供后续配置普通怪、必要奖励的初始可达空间，没有生成具体怪物或奖励。
没有单独设置必须依赖随机能力的区域；高台初始到达依赖未来连接实现，能力可再提供捷径。

## 数据约定

- 世界尺寸 {config['world_size_m'][0]}×{config['world_size_m'][1]}m，基础数据图每像素 2×2m；两图同尺寸、同原点、同方向。
- 原点以地图中心为参考：左上边界为 (-W/2,-D/2)，右为 +X，下为 +Z。
- 像素 (u,v) 表示一个完整地块；其中心 X=-W/2+(u+0.5)×2，Z=-D/2+(v+0.5)×2。
- 矩形按左上最小边界记录，最大边界不包含；世界单位米。JSON 中 `cell_xz` 的 z 为图像行。
- `biome_mask.png` 为 RGB、不透明四纯色 PNG；`height_map.png` 为 8 位 L 灰度 PNG，无插值、抗锯齿或渐变。
- 读取灰度时直接读整数值，禁止按 sRGB、光照或自动归一化重新拉伸；用于数据的采样应为 nearest。
- 生态与高度独立读取，黑色不是水域标志，也不是空格。水域只通过生态 ID=3 识别。

|生态 ID|名称|RGB|HEX|面积占比|
|---|---|---|---|---|
"""
    for b in stats:
        text += f"|{b['id']}|{b['name']}|{tuple(b['rgb'])}|{b['hex']}|{b['area_percent']:.3f}%|\n"
    text += f"""
|灰度|相对陆地基准|实际世界 Y|v8 最高实体层 L|含义|
|---|---|---|---|---|
"""
    for b in config["height_bands"]:
        y=config['baseline_world_y_m']+b['relative_m']
        text += f"|{b['gray']}|{b['relative_m']:+d}m|{y}m|{int(y/2-1)}|{b['meaning']}|\n"
    text += f"""
陆地最高相对高度建议 +4m；含水底的总地面起伏为 6m。基准地面世界 Y={config['baseline_world_y_m']}m，
遵守 v8 顶面 `surface_y(L)=(L+1)×2m`，不把相对 0m 误当成世界 Y=0。
未来导入连续实体地形时，应显式填充第 0..L 层并使用分层 API；本模板不表达悬空、洞穴或多个外露表面。

水域高度图表达水底实体顶面，实际 Y={config['baseline_world_y_m']-2}m；另在 metadata 规定建议水面 Y={config['water_surface_world_y_m']}m。
水深为 {config['water_surface_world_y_m']-(config['baseline_world_y_m']-2)}m，岸地高于水面 {config['baseline_world_y_m']-config['water_surface_world_y_m']}m，避免高位水域。
该水面是另行约定的设计水位，PNG 并未编码水面；目前未验证现有液体附件能直接表达该水深，未来导入适配器必须落实水底/水面与碰撞。

## 候选位置与容纳检查

|候选|中心世界 X/Z（m）|占地|含衔接预留|入口世界 X/Z（m）|
|---|---|---|---|---|
"""
    for s in sites:
        c=s['center_world_xyz_m']; e=s['entrance_world_xyz_m']; sz=s['size_m']; outer=s['reservation_with_margin']['size_m']
        text += f"|{s['id']}|({c[0]:g}, {c[2]:g})|{sz[0]}×{sz[1]}m|{outer[0]}×{outer[1]}m|({e[0]:g}, {e[2]:g})|\n"
    text += f"\n出生 S1 世界坐标为 {spawn['world_xyz_m']}，完整点位见 `planning_markers.json` 与 CSV。\n"
    text += """
中心世界坐标为占地矩形的精确几何中心；偶数格宽矩形的中心位于格边界，`center_cell_xz` 只是邻近代表格。
入口坐标指框外具有通路净空的入口接近点，并非尚未提供的真实关卡内部门坐标。
已逐格检查候选框及整圈衔接带的生态、平整度、越界与相互冲突；出生/成长空间也参与预留冲突检查。
这些框用于空间容量验证，不能替代真实预制的占用掩码、旋转、生态 Tag 与内部地形检查。
未来先嵌入传送门与大关卡，再放小预制和固定怪点，并重新检查入口与路线。
12m 预留不是传送门清场半径；清场范围、怪物距离、挑战数量与时间配置仍待策划确定。

## 已检查的实际步行路线

四邻接 A*，每步 2m，只走同一基准高度的干燥陆地，禁止水域和所有跨层边（连下行也禁止，取保守规则）。
路线中心经过方形净空腐蚀检查，确保至少 8m 净宽；使用曼哈顿路径长度，不以直线距离代替步行。
寻路时把所有候选占地及外围衔接预留当作障碍，靠近目标后仅开放该目标的衔接带，终点停在其入口外的净空位置。
因此其他挑战内部如何变化，不会被本次必要路线偷穿；未来放入实际资产后仍须复验。
本稿只提供 S1/P1 一组候选，已检查这一组合，没有声称不存在的其他候选组合也合法。

|路线|二维网格步行距离|跨层连接|
|---|---|---|
"""
    for r in routes:
        text += f"|{r['from']} → {r['to']}|{r['length_m']}m|不使用|\n"
    text += f"""
`routes.json` 保存完整格坐标及世界坐标折线，可读取、复画和复验。路线为平地通行走廊，不改变生态颜色，不表示已经铺设道路。
G1–G3 分别为草原、岩地、沙漠成长候选，均可从出生到达，也已检查回到传送门的路线。
陆地基准平地占干燥陆地的 {checks['baseline_land_area_percent_of_dry_land']:.3f}%，且为一个连续区。
总时限、激活时刻、移动速度、实际碰撞半径均未给出，不承诺任何赶路秒数。

## 仅规划的跨层连接

T1/T2/T3 是宽 12m 的并排阶梯候选：每条升高 2m，阶梯水平长度 4m，两端各保留 2m 落脚带，总长 8m。
已检查每条并排车道低/高端格的生态及高度，尚未实例化阶梯或验证坡道碰撞，**没有计入上表必要通路**。

|连接|低端世界 XYZ（m）|高端世界 XYZ（m）|宽度|
|---|---|---|---|
"""
    for c in connections:
        text += f"|{c['id']}|{c['low_world_xyz_m']}|{c['high_world_xyz_m']}|{c['width_m']}m|\n"
    text += """
T1 为岩地基准平地到 +2m 台地，T2 为该台地到 +4m 高台，T3 为沙漠基准平地到 +2m 台地。
高台暂不放必要成长资源或传送门。连接完成前，不把高台声称为已验证的初始可探索区。

## 生成与调整

运行环境需要 Python、numpy、Pillow。工具与配置保存在专用工作区 `personal_workspace/shutiao_map/tools/`。
在专用工作区目录中运行：

```powershell
python tools/generate_world_map_template.py --config tools/world_map_template_v01.json --output output/world_map_template_v02
```

交付 ZIP 内也附生成脚本。解压后在模板目录执行：

```powershell
python tools/generate_world_map_template.py --config generation_config.json --output generated_v02
```

修改 `world_size_m` 可调整世界尺寸（各轴为 2m 整数倍，上限 1200m，符合项目 600 格上限）。
多边形控制点使用 0–1 归一化坐标，调整 `biome_polygons_normalized` 改变布局与面积比例；本稿实际比例为计算结果，不宣称精确目标比例。
`plateaus` 控制高差块面；候选中心随尺寸归一化移动，而关卡实际 100m、传送门 30m、衔接带和通路宽度保持米数。
缩小尺寸或大改边界后，空间或通路不足会报错，应调整参数后重生成，不能把 100m 关卡偷偷缩小。
生成无随机过程，参数完整保存于 `generation_config.json`；默认拒绝覆盖已有输出，`--replace-generated` 只允许更新本工具标记的目录。
本工具只允许写入脚本所属工作区内的子目录；默认输出也随脚本位置确定，不写工程公共目录。

## 验证与限制

`validation_report.json` 记录 PNG 回读、精确色值、逐像素对应、生态连续性、平地连通、候选整圈预留与 8m 通道验证。
全部路径均未使用 T1–T3；所有陆地相邻高差最大 2m，无从基准平地直接跳到 +4m 的意外断层。
已验证的是本模板二维数据；未生成 LevelData、导入接口、正式地表贴图、三维场景、可交互关卡或独立 Boss 战场。
真实预制嵌入后的接缝、坡道/阶梯、物理碰撞、导航、视觉遮挡、水体表现、怪物与奖励规则、GUI 仍需后续三维验收。
不把二维路径或 Godot 无窗口检查当作游戏可玩验收。

## 文件

- `biome_mask.png` / `height_map.png`：无标记基础数据。
- `map_preview.png`：带图例、尺寸、候选框、初始路线和阶梯规划的检查图。
- `biome_preview.png` / `height_preview.png`：3 倍最近邻放大的无标记预览（高度预览为展示配色，不作数据输入）。
- `map_metadata.json`：坐标、编码、水位、v8 换算、生成参数引用及交付文件 SHA-256。
- `planning_markers.json` / `.csv`：候选坐标、占地、衔接范围、入口。
- `routes.json` / `connections.json`：可读取通路及规划连接。
- `validation_report.json` / `generation_config.json`：检查证据与复现参数。
- `.gdignore`：避免 Godot 把数据 PNG 当材质图导入、把坐标 CSV 当翻译表导入；后续专用读取器可按文件路径读取。
"""
    (output/"map_notes.md").write_text(text,encoding="utf-8")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config",type=Path,default=ROOT/"tools/world_map_template_v01.json")
    parser.add_argument("--output",type=Path,default=ROOT/"output/world_map_template_v01")
    parser.add_argument("--replace-generated",action="store_true")
    args=parser.parse_args()
    output=checked_output(args.output)
    if output.exists():
        marker=output/"map_metadata.json"
        if not args.replace_generated or not marker.exists() or json.loads(marker.read_text(encoding="utf-8")).get("generator") != GENERATOR:
            raise FileExistsError(f"Refusing to overwrite existing or unrecognized output: {output}")
    config=json.loads(args.config.read_text(encoding="utf-8"))
    generate(config,output)
    archive=output.with_suffix(".zip")
    with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED) as z:
        for name in (*DELIVERY_FILES, "map_metadata.json"):
            z.write(output/name,output.name+"/"+name)
        z.write(Path(__file__),output.name+"/tools/"+Path(__file__).name)
    print(f"Archive: {archive}")


if __name__ == "__main__":
    main()
