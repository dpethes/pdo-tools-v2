package;

import haxe.io.Bytes;
import js.Browser;
import js.html.ArrayBuffer;
import js.html.Uint8Array;
import js.html.XMLHttpRequest;


class PdoV2Reader
{
	var current_idx = 0;
	var buf:Bytes;
	
	public function new (buffer:Bytes) {		
		buf = buffer;
	}
	
	public function ReadLine(): String {
		var i = current_idx;
		while (buf.get(i) != 10 && i < buf.length) {
			i += 1;
		}		
		var res:String = buf.getString(current_idx, i - current_idx);
		current_idx = i + 1;
		return res;
	}
	
	public function ReadLineSplit(): Array<String> {
		return ReadLine().split(" ");
	}
	
	public function ReadBuffer(size:Int): Bytes {
		var res = buf.sub(current_idx, size);
		current_idx = current_idx + size + 1;  //skip 0x10 after texture data
		return res;
	}
}

class PdoV2Parser
{
	var p:PdoV2Reader;
	
	public function new(reader:PdoV2Reader) {
		p = reader;
	}
	
	public function Parse() 
	{
		var m: String;
		m = p.ReadLine();  //# Pepakura Designer Work Info ver 2
		m = p.ReadLine();  //#
		m = p.ReadLine();  //
		m = p.ReadLine();  //version 2
		m = p.ReadLine();  //min_version 2
		m = p.ReadLine();  //
		m = p.ReadLine();  //model
		
		var solids_num = Std.parseInt(p.ReadLineSplit()[1]); //solids %d
		for (i in 0...solids_num) {
			m = p.ReadLine();  //solid
			var solid_name = p.ReadLine();
			m = p.ReadLine();  //1
			
			var vertices_num = Std.parseInt(p.ReadLineSplit()[1]);  //"vertices %d"
			for (vertex_i in 0...vertices_num) {
				var coords_str = p.ReadLineSplit();  //"%f %f %f" - X/Y/Z floats
				var x = Std.parseFloat(coords_str[0]);
				var y = Std.parseFloat(coords_str[1]);
				var z = Std.parseFloat(coords_str[2]);
				trace(x + " " + y + " " + z);
			}
			
			var faces_num = Std.parseInt(p.ReadLineSplit()[1]);  //faces %d
			trace("faces: " + faces_num);
			for (face_i in 0...faces_num) {
				var face_str = p.ReadLineSplit();  //%d %d %f %f %f %f %d
				var material_index = Std.parseInt(face_str[0]);
				var vertices2d_num = Std.parseInt(face_str[6]);
				trace("face " + face_i + " vertices: " + vertices2d_num);
				for (vertex2d_i in 0...vertices2d_num) {
					var vertex2d_str = p.ReadLineSplit();
					/*  "%d" - index of 3D vertex
						+ " %f %f %f %f" - 2D X, 2D Y, texture U, texture V
						+ " %d %f %f" - ?, ?, ? 
						*/
				}
			}
			
			var edges_num = Std.parseInt(p.ReadLineSplit()[1]); //edges %d
			trace("edges: " + edges_num);
			for (edge_i in 0...edges_num) {
				var edge_str = p.ReadLineSplit();
			}
		}
		
		m = p.ReadLine(); //"defaultmaterial"
		m = p.ReadLine(); //"material"
		m = p.ReadLine(); //empty
		var matstr_temp = p.ReadLineSplit();  //default material settings
		var materials_num = Std.parseInt(p.ReadLineSplit()[1]); //materials %d
		for (material_i in 0...materials_num) {
			m = p.ReadLine();  //"material"
			var material_name = p.ReadLine();
			trace("material: " + (material_name != "" ? material_name : "(unnamed)"));
			var material_str = p.ReadLineSplit();
			for (color_setting_i in 0...5) {
				trace('color idx: $color_setting_i');
				var base = color_setting_i * 4;
				var r = material_str[base + 1];  //todo check color ordering
				var g = material_str[base + 2];
				var b = material_str[base + 3];
				var a = material_str[base + 0];
				trace('color: ($r, $g, $b, $a)');
			}
			var texture_flag = Std.parseInt(material_str[21]);
			trace('tex: $texture_flag');
			if (texture_flag == 1) {
				m = p.ReadLine();  //empty
				var wxh_str = p.ReadLineSplit();
				var tex_width  = Std.parseInt(wxh_str[0]);
				var tex_height = Std.parseInt(wxh_str[1]);
				trace('texture $tex_width x $tex_height');
				var tex_data = p.ReadBuffer(tex_width * tex_height * 3);
			}
		}
		
		var parts_num = Std.parseInt(p.ReadLineSplit()[1]); //parts %d
		trace('parts: $parts_num');
		for (part_i in 0...parts_num) {
			var part_param = p.ReadLineSplit();
		}
		
		var texts_num = Std.parseInt(p.ReadLineSplit()[1]); //text %d
		trace('texts: $texts_num');
		for (text_i in 0...texts_num) {
			var text_unknown = Std.parseInt(p.ReadLine());
			var font_name = p.ReadLine();
			var text = p.ReadLine();
			var text_params = p.ReadLineSplit();
		}
		
		m = p.ReadLine(); //info
		for (info_i in 0...31) {
			m = p.ReadLine();
			trace(m);
		}

		var doc = Browser.document;  
		var view = doc.createDivElement();
		view.className = 'view';
		view.textContent = "reading finished";
		doc.body.appendChild(view);
	}
}

class Main 
{
	static function main() 
	{
		//file to open
		var file_name = "dice.pdo";
				
		//Read local file through XMLHttpRequest, because JS has no "read bytes from file" api.
		//Haxe.Http returns data as string, this messes up binary data so it can't be used.
		//Oh and binary data request works only in async mode - sync can't use responseType.
		//So do all work in a callback.
		var req = new XMLHttpRequest();
		req.open("GET", file_name);
		req.responseType = js.html.XMLHttpRequestResponseType.ARRAYBUFFER;

		req.onload = function(event) {
			var array_buf: ArrayBuffer = req.response;
			var u8_array = new Uint8Array(array_buf);
			
			//todo figure out a sane way to convert the Uint8Array to Bytes
			var bytes_buf = Bytes.alloc(u8_array.length);
			for (i in 0...u8_array.length) {
				bytes_buf.set(i, u8_array[i]);
			}
			trace(bytes_buf.length);
			
			var reader = new PdoV2Reader(bytes_buf);
			var parser = new PdoV2Parser(reader);
			parser.Parse();
		}
		
		req.send();
	}	
}