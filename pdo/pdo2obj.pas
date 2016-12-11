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
end;

end.

