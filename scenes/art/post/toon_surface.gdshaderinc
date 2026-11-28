// What a toon mesh's surface carries besides its colour (Art, `toon_material.gd`): the instance
// uniforms `toon.gdshader`, `toon_tex.gdshader` and `toon_parts.gdshader` share (the kit's decal
// has none of them; a merged chunk takes the same from its vertices).

// The mesh kit's faces carry their own colour (the vertex colour, white on a mesh without one);
// base_color tints the whole instance.
instance uniform vec4 base_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);
// A figure (Art, `MeshNodes.figure`; 1 = a character's part): written as the roughness into the
// normal buffer, which the outline pass reads to draw a figure's silhouette only, no creases.
instance uniform float figure : hint_range(0.0, 1.0) = 0.0;
// A glow whatever the light (Art, `MeshNodes.glow`): rgb the colour, a the strength; 0 is none.
instance uniform vec4 emissive : source_color = vec4(0.0);
