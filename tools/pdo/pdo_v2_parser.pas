unit pdo_v2_parser;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  pdo_v2, utils;

type
  { TPdoV2FileStream }

  TPdoV2FileStream = class (TMemoryStream)
  private
    procedure ReadEmptyLine;
    public
      function ReadStrBuffer(const count: integer): string;
      function ReadLine: string;
  end;

  { TPdoV2Parser }

  TPdoV2Parser = class
    private
      _d: TPdoV2Document;
      _f: TPdoV2FileStream;
      function ReadFace: TPdoV2Face;
      function ReadMaterial: TPdoV2Material;
      function ReadObject: TPdoV2Solid;
    public
      Error: procedure (s: string);
      constructor Create();
      destructor Destroy; override;
      procedure OpenFile(file_name: string);
      procedure Load;
      function GetDocument: TPdoV2Document;
      procedure ReadObjects;
      procedure ReadMaterials;
      procedure ReadParts;
      procedure ReadTexts;
      procedure ReadSettings;
  end;


{**************************************************************************************************}
implementation


procedure console_write_error(s: string);
begin
  writeln(s);
  halt;
end;

{ TPdoV2FileStream }

function TPdoV2FileStream.ReadStrBuffer(const count: integer): string;
var
  i: Integer;
begin
  result := '';
  for i := 1 to count do
      result += char(ReadByte);
end;

function TPdoV2FileStream.ReadLine(): string;
var
  c: byte;
begin
  result := '';
  c := ReadByte;
  while c <> 10 do begin
    result += char(c);
    c := ReadByte;
  end;
end;

procedure TPdoV2FileStream.ReadEmptyLine;
var
  r: String;
begin
  r := ReadLine;
  Assert(r = '', 'empty line expected');
end;


{ TPdoParser }

constructor TPdoV2Parser.Create;
begin
  _d := TPdoV2Document.Create;
  _f := TPdoV2FileStream.Create;
  Error := @console_write_error;
end;

destructor TPdoV2Parser.Destroy;
begin
  _f.Free;
  inherited Destroy;
end;

procedure TPdoV2Parser.OpenFile(file_name: string);
var
  s: string;
begin
  _f.LoadFromFile(file_name);
  if _f.Size < Length(PdoV2Magic) * 2 then
      Error('File too short!');
  //header magic
  s := _f.ReadStrBuffer(Length(PdoV2Magic));
  if s <> PdoV2Magic then
      Error('Not a valid Pepakura v2 file!');
end;

procedure TPdoV2Parser.Load;
var
  separator: Char;
begin
  //Pepakura uses dot as separator, we need to force it for float parsing to work if the locale uses
  //something else (comma for example)
  separator := FormatSettings.DecimalSeparator;
  FormatSettings.DecimalSeparator := '.';
  ReadObjects;
  ReadMaterials;
  ReadParts;
  ReadTexts;
  ReadSettings;
  FormatSettings.DecimalSeparator := separator;
end;

function TPdoV2Parser.GetDocument: TPdoV2Document;
begin
  result := _d;
end;


procedure TPdoV2Parser.ReadObjects;
var
  model: string;
  solids_num, i: integer;
begin
  model := _f.ReadLine;  //'model %f %f %f %f %f %f'
  SScanf(_f.ReadLine, 'solids %d', [@solids_num]);
  _d.object_count := solids_num;
  SetLength(_d.objects, solids_num);
  for i := 0 to solids_num - 1 do begin
      _d.objects[i] := ReadObject();
  end;
end;


function TPdoV2Parser.ReadObject: TPdoV2Solid;
var
  o: TPdoV2Solid;
  v: TPdoV2Vertex3D;
  e: TPdoV2Edge;
  i: Integer;
  s: String;
begin
  s := _f.ReadLine;
  Assert(s = 'solid');
  o.name := _f.ReadLine;
  o.visible := _f.ReadLine = '1';

  begin //vertices
      SScanf(_f.ReadLine, 'vertices %d', [ @o.vertex_count]);
      SetLength(o.vertices, o.vertex_count);
      for i := 0 to o.vertex_count - 1 do begin
          s := _f.ReadLine;
          Scan(s, '%f %f %f', [@v.x, @v.y, @v.z]);
          o.vertices[i] := v;
      end;
  end;

  begin //faces
      SScanf(_f.ReadLine, 'faces %d', [ @o.face_count]);
      SetLength(o.faces, o.face_count);
      for i := 0 to o.face_count - 1 do begin
          o.faces[i] := ReadFace;
      end;
  end;

  begin //edges
      SScanf(_f.ReadLine, 'edges %d', [ @o.edge_count]);
      SetLength(o.edges, o.edge_count);
      for i := 0 to o.edge_count - 1 do begin
          s := _f.ReadLine;
          Scan(s, '%d %d %d %d %d %b',
              [@e.face1_index, @e.face2_index,
               @e.vertex1index, @e.vertex2index,
               @e.u1b, @e.cut_edge]);
          o.edges[i] := e;
      end;
  end;

  result := o;
end;

function TPdoV2Parser.ReadFace: TPdoV2Face;
var
  r: TPdoV2Face;
  v: TPdoV2Vertex2D;
  s: String;
  i: Integer;
begin
  s := _f.ReadLine;
  Scan(s, '%d %d %f %f %f %f %d',
          [@r.material_index, @r.part_index,
           @r.u4f[0],@r.u4f[1],@r.u4f[2],@r.u4f[3],
           @r.vertex_count]);
  SetLength(r.vertices, r.vertex_count);
  for i := 0 to r.vertex_count - 1 do begin
    s := _f.ReadLine;
    Scan(s, '%d %f %f %f %f %d %d %f',
            [@v.vertex3d_idx, @v.x, @v.y, @v.u, @v.v,
             @v.has_flap, @v.has_edge_line, @v.flap_height]);
    r.vertices[i] := v;
  end;
  result := r;
end;

function TPdoV2Parser.ReadMaterial: TPdoV2Material;
var
  r: TPdoV2Material;
  s: String;
  color: psingle; //color 3D pointer
  size: integer;
begin
  s := _f.ReadLine;
  Assert(s = 'material');
  r.name := _f.ReadLine;
  s := _f.ReadLine;

  color := @r.color3d_rgba[0];
  Scan(s, '%f %f %f %f' + ' %f %f %f %f' + ' %f %f %f %f' + ' %f %f %f %f'
          + ' %f %f %f %f' + ' %d %b',
         [@color[0],  @color[1],  @color[2], @color[3],
          @color[4],  @color[5],  @color[6], @color[7],
          @color[8],  @color[9],  @color[10], @color[11],
          @color[12], @color[13], @color[14], @color[15],
          @r.color2d_argb[0],  @r.color2d_argb[1],  @r.color2d_argb[2], @r.color2d_argb[3],
          @r.u1b, @r.has_texture
          ]);
  if r.has_texture then begin
      _f.ReadEmptyLine;
      Scan(_f.ReadLine, '%d %d', [@r.texture.width, @r.texture.height]);
      size := r.texture.width * r.texture.height * 3;
      r.texture.data := GetMem(size);
      _f.Read(r.texture.data^, size);
      _f.ReadEmptyLine;
  end;
  result := r;
end;


procedure TPdoV2Parser.ReadMaterials;
var
  s: String;
  i: Integer;
begin
  s := _f.ReadLine;
  Assert(s = 'defaultmaterial');
  ReadMaterial;   //ignore default material

  s := _f.ReadLine;
  SScanf(s, 'materials %d', [@_d.material_count]);
  SetLength(_d.materials, _d.material_count);
  for i := 0 to _d.material_count - 1 do begin
      _d.materials[i] := ReadMaterial;
  end;
end;

procedure TPdoV2Parser.ReadParts;
var
  p: TPdoV2Part;
  i: Integer;
  s: String;
begin
  SScanf(_f.ReadLine, 'parts %d', @_d.part_count);
  SetLength(_d.parts, _d.part_count);
  for i := 0 to _d.part_count - 1 do begin
      s := _f.ReadLine;
      Scan(s, '%d %f %f %f %f',
              [@p.object_index, @p.left, @p.top, @p.width, @p.height]);
      _d.parts[i] := p;
  end;
end;

procedure TPdoV2Parser.ReadTexts;
var
  t: TPdoV2Text;
  s: String;
  i: Integer;
  color: array[0..3] of integer;
begin
  SScanf(_f.ReadLine, 'text %d', @_d.text_count);
  SetLength(_d.texts, _d.text_count);
  for i := 0 to _d.text_count - 1 do begin
      Scan(_f.ReadLine, '%d', [@t.u1i]);
      t.font_name := _f.ReadLine;
      t.text := _f.ReadLine;
      s := _f.ReadLine;
      Scan(s, '%d %f %f %f %f' + ' %d %d %d %d',
              [@t.font_size, @t.x, @t.y, @t.u2f[0], @t.u2f[1],
               @color[0], @color[1], @color[2], @color[3]]);
      t.color_argb[0] := byte(color[0]);
      t.color_argb[1] := byte(color[1]);
      t.color_argb[2] := byte(color[2]);
      t.color_argb[3] := byte(color[3]);
      _d.texts[i] := t;
  end;
end;

procedure TPdoV2Parser.ReadSettings;
var
  s: string;
begin
  s := _f.ReadLine;  //  'info'
  s := _f.ReadLine;  //  'key %s' - not really a key
  s := _f.ReadLine;  //  'iLLevel %d'         - always 0?
  s := _f.ReadLine;  //  'dMag3d %f
  s := _f.ReadLine;  //  'dMag2d %f'          - 2D pattern scaling
  Scan(s, 'dMag2d %f', [@_d.info.dMag2d]);
  s := _f.ReadLine;  //  'dTenkaizuX %f
  s := _f.ReadLine;  //  'dTenkaizuY %f
  s := _f.ReadLine;  //  'dTenkaizuWidth %f'  - 2D pattern width
  s := _f.ReadLine;  //  'dTenkaizuHeight %f' - 2D pattern height
  s := _f.ReadLine;  //  'dTenkaizuMargin %f
  s := _f.ReadLine;  //  'bReverse %d
  s := _f.ReadLine;  //  'bFinished %d
  s := _f.ReadLine;  //  'iAngleEps %d
  s := _f.ReadLine;  //  'iTaniLineType %d
  s := _f.ReadLine;  //  'iYamaLineType %d
  s := _f.ReadLine;  //  'iCutLineType %d
  s := _f.ReadLine;  //  'bTextureCoodinates %d
  s := _f.ReadLine;  //  'bDrawFlap %d'           - show flaps
  s := _f.ReadLine;  //  'bDrawNumber %d'         - show edge ID
  s := _f.ReadLine;  //  'bUseMaterial %d
  s := _f.ReadLine;  //  'iEdgeNumberFontSize %d' - edge ID font size
  s := _f.ReadLine;  //  'bNorishiroReverse %d
  s := _f.ReadLine;  //  'bEdgeIdReverse %d'      - place edge ID outside face
  s := _f.ReadLine;  //  'bEnableLineAlpha %d
  s := _f.ReadLine;  //  'dTextureLineAlpha %f
  s := _f.ReadLine;  //  'bCullEdge %d
  s := _f.ReadLine;  //  'iPageType %d
  s := _f.ReadLine;  //  'dPageMarginSide %f
  s := _f.ReadLine;  //  'dPageMarginTop %f
  //TODO optional stuff
end;



end.

