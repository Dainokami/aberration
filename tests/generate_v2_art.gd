extends SceneTree

## Original procedural placeholder illustrations, not scraped production artwork.
func _init() -> void:
	var folder := "res://assets/placeholders/v2"
	DirAccess.make_dir_recursive_absolute(folder)
	var drawings := {
		"tree": '<path d="M122 222L110 109L143 109L143 223Z" fill="#76513d" stroke="#302f37" stroke-width="6"/><path d="M121 215L124 153M137 170L131 143" stroke="#ba8051" stroke-width="4"/><path d="M43 121Q16 88 59 68Q48 29 97 34Q126 3 155 35Q212 26 204 70Q245 103 213 136Q182 163 133 143Q76 165 43 121Z" fill="#61864f" stroke="#303e37" stroke-width="7"/><path d="M58 87Q88 56 117 67M142 46Q166 44 184 68M156 114Q190 100 202 116M72 127L96 118" fill="none" stroke="#92a761" stroke-width="10" stroke-linecap="round"/>',
		"trunk": '<path d="M122 222L110 109L143 109L143 223Z" fill="#76513d" stroke="#302f37" stroke-width="6"/><path d="M121 215L124 153M137 170L131 143" stroke="#ba8051" stroke-width="4"/>',
		"crown": '<path d="M43 121Q16 88 59 68Q48 29 97 34Q126 3 155 35Q212 26 204 70Q245 103 213 136Q182 163 133 143Q76 165 43 121Z" fill="#61864f" stroke="#303e37" stroke-width="7"/><path d="M58 87Q88 56 117 67M142 46Q166 44 184 68M156 114Q190 100 202 116" fill="none" stroke="#92a761" stroke-width="10" stroke-linecap="round"/>',
		"rock": '<path d="M31 184L44 120L92 68L166 72L222 126L230 193L181 222L74 221Z" fill="#898387" stroke="#383542" stroke-width="7"/><path d="M44 120L103 113L166 72L172 147L222 126M103 113L82 189L31 184M82 189L181 222L172 147Z" fill="#a59c98" stroke="#615b68" stroke-width="5"/><path d="M68 130L89 122M112 93L140 85" stroke="#d3c3ad" stroke-width="8" stroke-linecap="round"/>',
		"tent": '<path d="M26 204L101 43L231 182L191 222L83 220Z" fill="#b15f50" stroke="#3b3440" stroke-width="7"/><path d="M101 43L83 220L191 222Z" fill="#db9b69" stroke="#3b3440" stroke-width="6"/><path d="M101 101L102 214L159 216Z" fill="#41383f"/><path d="M35 192L63 199M122 72L205 175" stroke="#e1bb82" stroke-width="7"/><path d="M21 219L31 180M220 210L230 174" stroke="#755040" stroke-width="8"/>',
		"fence": '<path d="M29 85L39 221L55 219L49 77ZM199 71L209 219L225 215L218 63Z" fill="#bd8854" stroke="#40353c" stroke-width="6"/><path d="M35 105L215 90L217 119L38 136ZM39 164L218 148L220 177L42 194Z" fill="#956746" stroke="#40353c" stroke-width="6"/><path d="M66 117L171 108M84 176L190 162" stroke="#d0a167" stroke-width="5"/>',
		"grass": '<path d="M51 221Q56 173 31 136Q88 155 91 207Q90 153 108 104Q133 161 125 204Q146 146 183 132Q161 177 164 210Q192 171 223 168L196 220Z" fill="#6f9954" stroke="#36483d" stroke-width="6"/><path d="M108 213L108 145M147 214L167 164M72 212L58 169" stroke="#b0bc68" stroke-width="5"/>'
	}
	for key: String in drawings:
		var image := Image.new()
		var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">' + drawings[key] + '</svg>'
		var error := image.load_svg_from_string(svg)
		if error != OK:
			quit(1)
			return
		var path := folder.path_join(key + ".png")
		if not FileAccess.file_exists(path):
			assert(image.save_png(path) == OK)
	print("V2 original placeholder PNGs ready")
	quit()
