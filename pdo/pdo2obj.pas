unit pdo2obj;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, math,
  pdo_v2, utils;

type
  TObjExportOptions = record
      normalize: boolean;
      flip_v_coordinate: boolean;
  end;

//Writes 3d object to Wavefront obj format.
procedure WriteObj(const pdo: TPdoV2Document; const obj_name: string; const opts: TObjExportOptions);

implementation

const
  HeaderComment = 'Created with PdoTools';
  DefaultMaterial = 'default';

{
  StoreTexture
  Save texture in TGA format: needs to swap pixels from RGB to BGR order that TGA uses.
}
procedure StoreTexture(const fname: string; const pixdata: pbyte; const w, h: integer);
var
  i: integer;
  t: byte;
  size: integer;
  pixels: pbyte;
begin
  size := w * h * 3;
  pixels := getmem(size);
  move(pixdata^, pixels^, size);
  for i := 0 to w * h - 1 do begin
      t := pixels[i * 3];
      pixels[i * 3] := pixels[i * 3 + 2];
      pixels[i * 3 + 2] := t;
  end;
  WriteTga(fname, pixels, w, h, size);
  freemem(pixels);
end;


procedure SaveMaterials(const pdo: TPdoV2Document; const obj_name: string);
var
  mtl_file:TextFile;
  mat: TPdoV2Material;
  tex_counter: integer;
  tex_name, tex_name_prefix: string;

procedure WriteBaseAttrs;
begin
  writeln(mtl_file, 'Ka 1.000 1.000 1.000');  //ambient color
  writeln(mtl_file, 'Kd 1.000 1.000 1.000');  //diffuse color
  writeln(mtl_file, 'Ks 1.000 1.000 1.000');  //specular color
  writeln(mtl_file, 'Ns 100.0');              //specular weight
  writeln(mtl_file, 'illum 2');               //Color on and Ambient on, Highlight on
end;

procedure WriteMaterial(const name, texture: string);
begin
  writeln(mtl_file, 'newmtl ', name);  //begin new material
  if texture <> '' then
      writeln(mtl_file, 'map_Kd ' + texture);  //texture
end;

begin
  tex_name_prefix := obj_name + '_tex';

  AssignFile(mtl_file, obj_name + '.mtl');
  Rewrite(mtl_file);

  writeln(mtl_file, '# ' + HeaderComment);
  WriteMaterial(DefaultMaterial, '');
  WriteBaseAttrs;

  tex_counter := 0;
  for mat in pdo.materials do begin
      if mat.has_texture then begin
          tex_name := tex_name_prefix + IntToStr(tex_counter) + '.tga';
          tex_counter += 1;
          StoreTexture(tex_name, mat.texture.data, mat.texture.width, mat.texture.height);
      end else
          tex_name := '';
      WriteMaterial(mat.name, tex_name);
      WriteBaseAttrs;
      writeln(mtl_file);
  end;

  CloseFile(mtl_file);
end;


procedure WriteObj(const pdo: TPdoV2Document; const obj_name: string; const opts: TObjExportOptions);
const
  DesiredUnitSize = 2;
var
  objfile: TextFile;
  obj: TPdoV2Solid;
  vertex3d: TPdoV2Vertex3D;
  face: TPdoV2Face;
  vertex: TPdoV2Vertex2D;
  x, y, z: double;
  u, v: double;

  scaling_factor: double;
  coord_max: double;
  uv_counter: integer;
  vertex3d_offset: integer;
  last_material_index: integer;

function GetMaxCoord: double;
begin
  result := 0;
  for obj in pdo.objects do begin
      for vertex3d in obj.vertices do begin
          x := abs(vertex3d.x);
          y := abs(vertex3d.y);
          z := abs(vertex3d.z);
          coord_max := Max(z, Max(x, y));
          if coord_max > result then
              result := coord_max;
      end;
  end;
end;

begin
  AssignFile(objfile, obj_name);
  Rewrite(objfile);

  writeln(objfile, '# ' + HeaderComment);
  writeln(objfile, 'mtllib ', obj_name + '.mtl');

  //scale pass
  scaling_factor := 1;
  if opts.normalize then begin
      scaling_factor := DesiredUnitSize / GetMaxCoord;
      //writeln(stderr, scaling_factor);
  end;

  //vertex pass
  for obj in pdo.objects do begin
      if not obj.visible then
          continue;
      for vertex3d in obj.vertices do begin
          x := (vertex3d.x) * scaling_factor;
          y := (vertex3d.y) * scaling_factor;
          z := (vertex3d.z) * scaling_factor;
          writeln(objfile, 'v ', x:10:6, ' ', y:10:6, ' ', z:10:6);
      end;
  end;

  //uv pass
  for obj in pdo.objects do begin
      if not obj.visible then
          continue;
      for face in obj.faces do begin
          for vertex in face.vertices do begin
              u := vertex.u;
              v := -vertex.v;
              if opts.flip_v_coordinate then
                  v := 1 - vertex.v;
              writeln(objfile, 'vt ', u:10:6, ' ', v:10:6);
          end;
      end;
  end;

  //face / material pass
  uv_counter := 0;
  vertex3d_offset := 1;
  last_material_index := -1;
  for obj in pdo.objects do begin
      if not obj.visible then
          continue;
      writeln(objfile, 'g ' + obj.name);
      for face in obj.faces do begin
          if face.material_index <> last_material_index then begin
              if face.material_index = -1 then
                  writeln(objfile, 'usemtl ' + DefaultMaterial)
              else
                  writeln(objfile, 'usemtl ' + pdo.materials[face.material_index].name);
              last_material_index := face.material_index;

          end;
          write(objfile, 'f ');
          for vertex in face.vertices do begin
              uv_counter += 1;
              write(objfile, vertex.vertex3d_idx + vertex3d_offset);
              write(objfile, '/', uv_counter);
              write(objfile, ' ');
          end;
          writeln(objfile);
      end;
      vertex3d_offset += Length(obj.vertices);
  end;

  CloseFile(objfile);

  SaveMaterials(pdo, obj_name);
end;

end.

