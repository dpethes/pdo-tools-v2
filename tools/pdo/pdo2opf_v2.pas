unit pdo2opf_v2;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl, math,
  pdo_v2, part_outliner,
  opf_common,
  progress_report, face2d_rasterizer, png_writer, utils;

const
  USE_MT = false;
  MIN_DPI = 100;  //low-res textures benefit from some interpolation, 100 looks nice

type
  { PdoToOpf2dTransform }

  PdoToOpf2dTransform = class
  private
      _pdo: TPdoV2Document;
      _parts: TOpfPart2dList;
      _log: TPartProgressLog;
      _tex_ctx: TTextureTableCtx;
      _dpi: integer;
      _dpi_min: integer;
      _page: TPageSetup;

      function GetMaxFaceDpi(const face: TOpfFace): integer;
      function IsJunkPart(const bb: TPdoRect): boolean;
      procedure SetupPageSize;
      procedure SetUsedFacesAndBB(const part: TPdoV2Part; const part_idx: integer; faces: array of TPdoV2Face; part2d: TOpfPart2d);
      procedure SinglePartRasterizeToPngStream(Index: PtrInt; Data: Pointer);
  public
      constructor Create(const pdo: TPdoV2Document);
      destructor Destroy; override;

      function GetParts: TOpfPart2dList;
      function GetPageSetup: TPageSetup;
      procedure PartsTo2D;
      procedure RasterizeToPngStream(const dpi: integer; dpi_min: integer = MIN_DPI);
      procedure DumpPng(const path: string);
  end;


//**************************************************************************************************
implementation

function OpfFacesToOutlinerFaces(const faces: TOpfFaceList): TOutlinerFaceList;
var
  face: TOpfFace;
  vertex_count: integer;
  outface: TOutlinerFace;
  i, f: Integer;
begin
  result := TOutlinerFaceList.Create;
  for f := 0 to faces.Count - 1 do begin
      face := faces[f];
      vertex_count := Length(face.vertices);
      SetLength(outface.vertices, vertex_count);
      for i := 0 to vertex_count - 1 do begin
          outface.vertices[i].x := face.vertices[i].x;
          outface.vertices[i].y := face.vertices[i].y;
      end;
      result.Add(outface);
  end;
end;

function PdoToOpfFace(const f: TPdoV2Face; const scale: single): TOpfFace;
    function ToOpfVert(const v: TPdoV2Vertex2D): TOpf2DVertex;
    begin
      result.x := v.x * scale;
      result.y := v.y * scale;
      result.u := v.u;
      result.v := v.v;
    end;
var
  r: TOpfFace;
  i: Integer;
begin
  r.material_index := f.material_index;
  SetLength(r.vertices, Length(f.vertices));
  for i := 0 to Length(f.vertices) - 1 do
       r.vertices[i] := ToOpfVert(f.vertices[i]);
  result := r;
end;


{ PdoToOpf2dTransform }

constructor PdoToOpf2dTransform.Create(const pdo: TPdoV2Document);
begin
  _pdo := pdo;
  _log := T2dTransformPartProgressLog.Create;
  _parts := TOpfPart2dList.Create;
end;

destructor PdoToOpf2dTransform.Destroy;
var
  i: Integer;
begin
  inherited Destroy;
  for i := 0 to _parts.Count - 1 do
      _parts[i].Free;
  _parts.Free;
end;


function PdoToOpf2dTransform.GetMaxFaceDpi(const face: TOpfFace): integer;
var
  i: Integer;
  max_span: single;
  tex_w, tex_h: integer;
  material_idx: integer;

  function GetSpan(const a, b: TOpf2DVertex): single;
  var
    dx, dy: single;
    du, dv: single;
    len: single;
  begin
    dx := abs(a.x - b.x);
    dy := abs(a.y - b.y);
    len := sqrt(dx*dx + dy*dy);
    du := abs(a.u - b.u) * tex_w;
    dv := abs(a.v - b.v) * tex_h;
    if len = 0 then
        result := 0
    else
        result := max(du/len, dv/len);
  end;

begin
  result := 0;
  material_idx := face.material_index;
  if (material_idx = -1) or not _pdo.materials[material_idx].has_texture then
      exit;

  tex_w := _pdo.materials[material_idx].texture.width;
  tex_h := _pdo.materials[material_idx].texture.height;
  max_span := GetSpan(face.vertices[0], face.vertices[Length(face.vertices) - 1]);
  for i := 0 to Length(face.vertices) - 2 do begin
      max_span := max(max_span, GetSpan(face.vertices[i], face.vertices[i + 1]));
  end;

  //round to multiplies of 10?
  result := ceil(max_span * 25.4);
end;

{ SetUsedFacesAndBB
  Find faces that belong to a part and calculate bounding box' width & height.
  Pdo part's bounding box contains flaps, so the BB must be calculated from vertex positions.
  Also try to pick optimal DPI based on texture span for each face. If faces don't use textures
  and use multiple materials, the DPI is boosted to have less visible aliasing between faces using
  different materials.
}
procedure PdoToOpf2dTransform.SetUsedFacesAndBB(const part: TPdoV2Part; const part_idx: integer;
  faces: array of TPdoV2Face; part2d: TOpfPart2d);
var
  vertex: TOpf2DVertex;
  face: TPdoV2Face;
  width, height: double;
  minx, miny: double;
  vertex_scale: single;
  face_dpi_max: integer;
  first_material: integer;
  multiple_materials: boolean;
  opf_face: TOpfFace;
begin
  width := 0;
  height := 0;
  //the left/top offset is due to flaps; max flap height shouldn't be above 1000, so use this as default
  minx := 1000;
  miny := 1000;
  part2d.dpi := 0;
  first_material := faces[0].material_index;
  multiple_materials := false;
  vertex_scale := _pdo.info.dMag2d * 10;

  for face in faces do begin
      if face.part_index <> part_idx then
          continue;

      opf_face := PdoToOpfFace(face, vertex_scale);
      part2d.faces.Add(opf_face);

      for vertex in opf_face.vertices do begin
          if vertex.x > width  then width  := vertex.x;
          if vertex.y > height then height := vertex.y;
          if vertex.x < minx  then minx := vertex.x;
          if vertex.y < miny  then miny := vertex.y;
      end;
      face_dpi_max := GetMaxFaceDpi(opf_face);
      part2d.dpi := Max(part2d.dpi, face_dpi_max);

      if first_material <> face.material_index then
          multiple_materials := true;
  end;

  if multiple_materials and (part2d.dpi = 0) then
      part2d.dpi := MIN_DPI * 3;

  part2d.bounding_box.left := part.left * vertex_scale;
  part2d.bounding_box.top  := part.top  * vertex_scale;
  part2d.bounding_box.width  := width;
  part2d.bounding_box.height := height;

  part2d.bounding_box_vert.left := minx;
  part2d.bounding_box_vert.top  := miny;
  part2d.bounding_box_vert.width  := width  - minx;
  part2d.bounding_box_vert.height := height - miny;
end;


{ Create2dElements
  create additional 2D elements - edges, foldlines, tabs
}
procedure Create2dElements(part2d: TOpfPart2d; const obj: TPdoV2Solid; const part: TPdoV2Part);
var
  outliner_faces: TOutlinerFaceList;
  edges: TEdgeList;
begin
  outliner_faces := OpfFacesToOutlinerFaces(part2d.faces);
  edges := FindOutlineEdges(outliner_faces);
  outliner_faces.Free;

  part2d.outline_paths := MergeEdgesToPaths(edges);
  part2d.outline_edges_debug := edges;  //unused behind this point, stored just for debug printing
end;


function PdoToOpf2dTransform.GetParts: TOpfPart2dList;
begin
  result := _parts;
end;

function PdoToOpf2dTransform.GetPageSetup: TPageSetup;
begin
  result := _page;
end;

function PdoToOpf2dTransform.IsJunkPart(const bb: TPdoRect): boolean;
begin
  result := false;
  if bb.top + bb.height < 0 - _page.margin_top then
      result := true;
  if bb.left + bb.width < 0 - _page.margin_side then
      result := true;
end;

procedure PdoToOpf2dTransform.SetupPageSize;
begin
  _page.width  := 200; //_pdo.info.iPageType?
  _page.height := 200;

  _page.margin_side := _pdo.info.dPageMarginSide;
  _page.margin_top  := _pdo.info.dPageMarginTop;

  _page.clipped_width  := _page.width  - 2 * _page.margin_side;
  _page.clipped_height := _page.height - 2 * _page.margin_top;
end;


procedure PdoToOpf2dTransform.PartsTo2D;
var
  part: TPdoV2Part;
  obj: TPdoV2Solid;
  part2d: TOpfPart2d;
  bb_top, bb_left: single;
  part_idx: integer;

begin
  _log.BeginWriting(Length(_pdo.parts));
  SetupPageSize;

  _parts.Capacity := Length(_pdo.parts);
  part_idx := 0;
  for part in _pdo.parts do begin
      obj := _pdo.objects[part.object_index];

      part2d := TOpfPart2d.Create();
      part2d.name := 'part' + IntToStr(part_idx);
      SetUsedFacesAndBB(part, part_idx, obj.faces, part2d);
      part_idx += 1;

      //throw away parts that are positioned out of pages
      if IsJunkPart(part2d.bounding_box) then begin
          part2d.Free;
          continue;
      end;

      Create2dElements(part2d, obj, part);

      //get real bounding box top/left position based on vertices.
      //Stored BB can be crappy - extended even beyond vertices and tabs
      bb_left := part2d.bounding_box.left + part2d.bounding_box_vert.left;
      bb_top  := part2d.bounding_box.top  + part2d.bounding_box_vert.top;
      part2d.page_w := floor( bb_left / _page.clipped_width );
      part2d.page_h := floor( bb_top / _page.clipped_height );

      _parts.Add(part2d);
      _log.PartWritten;
  end;
  _log.EndWriting;
end;

procedure PdoToOpf2dTransform.SinglePartRasterizeToPngStream(Index: PtrInt; Data: Pointer);
var
  rasterizer: TFace2dRasterizer;
  part: TOpfPart2d;
  face: TOpfFace;
  pixbuf: TRasterizerTexture;
  i: Integer;
  dpi: Integer;
begin
  part := TOpfPart2dList(Data)[Index];

  dpi := max(_dpi_min, min(part.dpi, _dpi));
  rasterizer := TFace2dRasterizer.Create(_tex_ctx);
  rasterizer.BeginPart(part.bounding_box_vert, dpi);

  for i := 0 to part.faces.Count - 1 do begin
      face := part.faces[i];
      rasterizer.RenderFace(face);
  end;
  pixbuf := rasterizer.GetPixelBuffer;
  part.png_stream := ImageToPngStream(pixbuf.pixels, pixbuf.width, pixbuf.height);
  part.png_w := pixbuf.width;
  part.png_h := pixbuf.height;
  freemem(pixbuf.pixels);

  rasterizer.EndPart;
  rasterizer.Free;
  _log.PartWritten;
end;

procedure PdoToOpf2dTransform.RasterizeToPngStream(const dpi: integer; dpi_min: integer);
var
  i: integer;
  mpix: int64;
begin
  _log.BeginWriting(_parts.Count);
  _tex_ctx := TFace2dRasterizer.BuildTextureTable(_pdo);
  _dpi := dpi;
  _dpi_min := dpi_min;

  if USE_MT then begin
  //    ProcThreadPool.DoParallel(@SinglePartRasterizeToPngStream, 0, _parts.Count - 1, _parts);
  end else begin
      for i := 0 to _parts.Count - 1 do
          SinglePartRasterizeToPngStream(i, _parts);
  end;

  TFace2dRasterizer.DestroyTextureTable(_tex_ctx);
  _log.EndWriting;

  mpix := 0;
  for i := 0 to _parts.Count - 1 do begin
      mpix += _parts[i].png_w * _parts[i].png_h;
  end;
  //writeln('MPix rendered: ', mpix / (1 shl 20):7:2);
end;

procedure PdoToOpf2dTransform.DumpPng(const path: string);
var
  part: TOpfPart2d;
  i: integer;
  name: string;
begin
  i := 0;
  for part in _parts do begin
      i += 1;
      name := path + 'part' + IntToStr(i);
      //name := name + '_dpi' + IntToStr(part.dpi);  //for DPI debugging
      part.png_stream.SaveToFile(name + '.png');
  end;
end;


end.

