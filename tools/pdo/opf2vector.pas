{
 Pdo tools - PDO format extraction and conversion tools
 Copyright (C) 2015 David Pethes

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 2
 of the License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
}
unit opf2vector;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl, math, contnrs,
  GenericStructList,
  pdo_v2, opf_common, part_outliner, tabs,
  vector_writer, svg_writer;

type
  TVecLayerMap = specialize TFPGMap<String, TVecLayerId>;

  TVectorExportFormat = (TvfPdf, TvfSvg);

  TVectorExportOptions = record
      tabs,
      foldlines,
      extended_foldlines,
      outlines,
      textures,
      faces,
      debug_edges: boolean;
  end;

  { TOpf2dVectorExport }

  TOpf2dVectorExport = class
    private
      _pdo: TPdoV2Document;
      _parts: TOpfPart2dList;
      _page: TPageSetup;
      _strmap: TFPStringHashTable;
      _layermap: TVecLayerMap;

      procedure DrawBasicParts(var pdfw: TVectorWriter; const parts: TOpfPart2dList);
      procedure DrawPageParts(var pdfw: TVectorWriter; const parts: TOpfPart2dList; const opts: TVectorExportOptions);
      procedure DrawTexturedParts(var pdfw: TVectorWriter;
        const opts: TVectorExportOptions; const parts: TOpfPart2dList;
        const pvertex_buffer: psingle);
      procedure InitLayers(var pdfw: TVectorWriter; const opts: TVectorExportOptions);
    public
      constructor Create(const pdo: TPdoV2Document; const parts: TOpfPart2dList; const page: TPageSetup);
      procedure Export2dParts(const file_name: string; const format: TVectorExportFormat; const opts: TVectorExportOptions);
  end;

implementation

{ TOpf2dVectorExport }

constructor TOpf2dVectorExport.Create(const pdo: TPdoV2Document; const parts: TOpfPart2dList;
  const page: TPageSetup);
begin
  _pdo := pdo;
  _parts := parts;
  _page := page;
end;

{ PartsWherePageXY
  Get parts that are on the page given by page coordinates.
}
function PartsWherePageXY(const parts: TOpfPart2dList; const x, y: integer): TOpfPart2dList;
var
  i: integer;
  in_page, has_outline: boolean;
begin
  result := TOpfPart2dList.Create;
  for i := 0 to parts.Count - 1 do begin
      in_page := (parts[i].page_w = x) and (parts[i].page_h = y);
      has_outline := parts[i].outline_paths.Count > 0;
      if in_page and has_outline then
          result.Add(parts[i]);
  end;
end;


{ InitLayers
  Define layers in bottom-to-top order
}
procedure TOpf2dVectorExport.InitLayers(var pdfw: TVectorWriter; const opts: TVectorExportOptions);
begin
  _layermap := TVecLayerMap.Create;
  _layermap.Add('tabs', pdfw.GenerateLayer('tabs'));
  _layermap.Add('foldlines-extended', pdfw.GenerateLayer('foldlines-extended'));
  _layermap.Add('faces', pdfw.GenerateLayer('faces'));
  _layermap.Add('textures', pdfw.GenerateLayer('textures'));
  _layermap.Add('outlines', pdfw.GenerateLayer('outlines'));
  _layermap.Add('foldlines', pdfw.GenerateLayer('foldlines'));
  _layermap.Add('texts', pdfw.GenerateLayer('texts'));
  if opts.debug_edges then
      _layermap.Add('debug', pdfw.GenerateLayer('debug'));
end;


{ Export2dParts
  Export 2D layout to vector file, either PDF or SVG.
}
procedure TOpf2dVectorExport.Export2dParts(const file_name: string;
  const format: TVectorExportFormat; const opts: TVectorExportOptions);
var
  pdfw: TVectorWriter;
  part: TOpfPart2d;
  parts: TOpfPart2dList;
  pages: record
      horizontal, vertical: integer;
  end;
  px, py: integer;

begin
  pages.horizontal := 0;
  pages.vertical := 0;
  for part in _parts do begin
      if part.page_w > pages.horizontal then
          pages.horizontal := part.page_w;
      if part.page_h > pages.vertical then
          pages.vertical := part.page_h;
  end;

  pdfw := TSvgWriter.Create();

  InitLayers(pdfw, opts);
  pdfw.InitDocProperties();

  for py := 0 to pages.vertical do begin
      for px := 0 to pages.horizontal do begin
          parts  := PartsWherePageXY (_parts, px, py);

          if parts.Count > 0 then begin
              pdfw.AddPage(_page.width, _page.height);
              pdfw.SetLineWidth(0.1);
              pdfw.SetCoordOffset(px * _page.clipped_width  - _page.margin_side,
                                  py * _page.clipped_height - _page.margin_top );

              DrawPageParts(pdfw, parts, opts);
          end;

          parts.Free;
      end;
  end;

  pdfw.SaveToFile(file_name);
  pdfw.Free;
  _strmap.Free;
  _layermap.Free;
end;


procedure TOpf2dVectorExport.DrawPageParts(var pdfw: TVectorWriter;
  const parts: TOpfPart2dList; const opts: TVectorExportOptions);
var
  pvertex_buffer: psingle;

  procedure ExtendLine(const Ax, Ay: single; var Bx, By: single);
  const
    LENGTH_EXTEND = 4;
  var
     dx, dy, length: single;
  begin
    dx := bx - ax;
    dy := by - ay;
    length := sqrt(dx * dx + dy * dy);
    bx := Ax + dx / length * (length + LENGTH_EXTEND);
    by := Ay + dy / length * (length + LENGTH_EXTEND);
  end;

  procedure DrawEdgeList(const edge_list: TEdgeList; const bbox: TPdoRect; const extended: boolean = false);
  var
    i: integer;
    Ax, Ay, Bx, By: single;
  begin
    for i := 0 to edge_list.Count - 1 do begin
        Ax := edge_list[i][0].x + bbox.left;
        Ay := edge_list[i][0].y + bbox.top;
        Bx := edge_list[i][1].x + bbox.left;
        By := edge_list[i][1].y + bbox.top;

        if extended then begin
            ExtendLine(Ax, Ay, Bx, By);
            ExtendLine(Bx, By, Ax, Ay);
        end;

        pvertex_buffer[0] := Ax;
        pvertex_buffer[1] := Ay;
        pvertex_buffer[2] := Bx;
        pvertex_buffer[3] := By;
        pdfw.DrawLine(pvertex_buffer);
    end;
  end;

  procedure DrawDebugLayer(var pdfw: TVectorWriter; const parts: TOpfPart2dList);
  var
    part: TOpfPart2d;
    bbox: TPdoRect;
    i: integer;
  begin
    pdfw.SetLayer(_layermap['debug']);
    pdfw.SetSolidLine();
    i := 0;
    for part in parts do begin
        bbox := part.bounding_box;
        DrawEdgeList(part.outline_edges_debug, bbox);
        //pdfw.Print(IntToStr(i), bbox.left, bbox.top, 6);
        pdfw.Print(part.name, bbox.left, bbox.top, 6);
        i += 1;
    end;
  end;

begin
  pdfw.SetLayer(_layermap['outlines']);
  pvertex_buffer := getmem(1 shl 20);

  //single-colored faces
  if opts.faces then
      DrawBasicParts(pdfw, parts);

  //textures + clipping + outline
  DrawTexturedParts(pdfw, opts, parts, pvertex_buffer);

  //debug info on top
  if opts.debug_edges then
      DrawDebugLayer(pdfw, parts);

  freemem(pvertex_buffer);
end;

{ PdoToOpf2dTransform
  Export part's outline and separately set the outline as the clipping path for part's bitmap.
}
procedure TOpf2dVectorExport.DrawTexturedParts(var pdfw: TVectorWriter;
  const opts: TVectorExportOptions;
  const parts: TOpfPart2dList;
  const pvertex_buffer: psingle);
var
  vertex_list: TVertexList;
  bbox: TPdoRect;
  vertex: TEdgeVertex;
  i: integer;
  part: TOpfPart2d;
  path_idx: integer;
  polys: array of TVectorPoly;
  vertex_buffer_current: psingle;
begin
  for part in parts do begin
      SetLength(polys, part.outline_paths.Count);
      vertex_buffer_current := pvertex_buffer;

      for path_idx := 0 to part.outline_paths.Count - 1 do begin
          vertex_list := part.outline_paths[path_idx];
          bbox := part.bounding_box;
          polys[path_idx].coords := vertex_buffer_current;
          polys[path_idx].count := vertex_list.Count;

          for i := 0 to vertex_list.Count - 1 do begin
              vertex := vertex_list[i];
              vertex_buffer_current[i * 2    ] := bbox.left + vertex.x;
              vertex_buffer_current[i * 2 + 1] := bbox.top  + vertex.y;
          end;

          vertex_buffer_current += vertex_list.Count * 2 * 4;
      end;

      pdfw.PushState;
      pdfw.SetClippingPolys(polys);

      if opts.textures then begin
          pdfw.SetLayer(_layermap['textures']);
          //use bounding box of the vertices - rasterized image contains only faces
          bbox.left += part.bounding_box_vert.left;
          bbox.top  += part.bounding_box_vert.top;
          bbox.width -= part.bounding_box_vert.left;
          bbox.height -= part.bounding_box_vert.top;
          pdfw.DrawPngImage(part.png_stream.Memory, part.png_stream.Size,
                            bbox.left, bbox.top + bbox.height,
                            bbox.width, bbox.height);
      end;

      if opts.outlines then begin
          pdfw.SetLayer(_layermap['outlines']);
          for path_idx := 0 to part.outline_paths.Count - 1 do
              pdfw.DrawPoly(polys[path_idx].coords, polys[path_idx].count);
      end;

      pdfw.PopState;
  end;
end;


{ DrawBasicParts
  Draw triangles or quads straight as they are defined in pdo
}
procedure TOpf2dVectorExport.DrawBasicParts(var pdfw: TVectorWriter; const parts: TOpfPart2dList);
var
  part: TOpfPart2d;
  bbox: TPdoRect;
  f: TOpfFace;
  v: TOpf2DVertex;
  k, i: Integer;
  vbuffer: array of Single;
begin
  pdfw.SetLayer(_layermap['faces']);
  pdfw.SetLineStyle(lsFace);
  SetLength(vbuffer, 2 * 4);
  for part in parts do begin
      bbox := part.bounding_box;
      for k := 0 to part.faces.Count - 1 do begin
          f := part.faces[k];
          if Length(vbuffer) < Length(f.vertices) * 2 then
              SetLength(vbuffer, Length(f.vertices) * 2);
          for i := 0 to Length(f.vertices) - 1 do begin
              v := f.vertices[i];
              vbuffer[2 * i]     := v.x + bbox.left;
              vbuffer[2 * i + 1] := v.y + bbox.top;
          end;
          pdfw.DrawPoly(@vbuffer[0], Length(f.vertices));
      end;
  end;
  pdfw.SetSolidLine;
  vbuffer := nil;
end;



end.

