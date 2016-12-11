unit pdo_v2;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  PdoV2Magic =
    '# Pepakura Designer Work Info ver 2' + #10 +
    '#' + #10 + 
    #10 +
    'version 2' + #10 +
    'min_version 2' + #10 + 
    #10;

type
  TPdoV2Vertex3D = record
      x, y, z: single;
  end;

  TPdoV2Vertex2D = record
      vertex3d_idx: integer;
      x: single;
      y: single;
      u: single;
      v: single;
      has_flap: boolean;
      has_edge_line: boolean;
      flap_height: single;
  end;

  TPdoV2Face = record
      material_index: integer;
      part_index: integer;
      u4f: array[0..3] of single;
      vertex_count: integer;
      vertices: array of TPdoV2Vertex2D;
  end;

  TPdoV2Edge = record
      face1_index: integer;
      face2_index: integer;
      vertex1index: integer;
      vertex2index: integer;
      u1b: byte;
      cut_edge: boolean;
  end;

  TPdoV2Solid = record
      name: string;
      visible: boolean;
      u1b: boolean;
      vertex_count: integer;
      face_count: integer;
      edge_count: integer;
      vertices: array of TPdoV2Vertex3D;
      faces: array of TPdoV2Face;
      edges: array of TPdoV2Edge;
  end;

  TPdoV2Texture = record
      width,
      height: integer;
      data: pbyte;
  end;

  TPdoV2Material = record
      name: string;
      color3d_rgba: array[0..15] of single;
      color2d_argb: array[0..3] of single;
      u1b: byte;
      has_texture: boolean;
      texture: TPdoV2Texture;
  end;

  TPdoV2Part = record
      object_index: integer;
      left, top, width, height: single;
  end;

  TPdoV2Text = record
      u1i: integer;
      font_name: string;
      text: string;
      font_size: integer;
      x, y: single;
      u2f: array[0..1] of single;
      color_argb: array[0..3] of byte;
  end;

  //ref type for more convenience
  TPdoV2Document = class
  public
      u6_f: array[0..5] of single;  //model info at beginning
      object_count: integer;
      material_count: integer;
      part_count: integer;
      text_count: integer;

      objects: array of TPdoV2Solid;
      materials: array of TPdoV2Material;
      default_material: TPdoV2Material;
      parts: array of TPdoV2Part;
      texts: array of TPdoV2Text;

      info: record
          key: array[0..31] of char;
          iLLevel: integer;
          dMag3d: single;
          dMag2d: single;
          dTenkaizuX: single;
          dTenkaizuY: single;
          dTenkaizuWidth: single;
          dTenkaizuHeight: single;
          dTenkaizuMargin: single;
          bReverse: boolean;
          bFinished: boolean;
          iAngleEps: integer;
          iTaniLineType: integer;
          iYamaLineType: integer;
          iCutLineType: integer;
          bTextureCoodinates: boolean;
          bDrawFlap: boolean;
          bDrawNumber: boolean;
          bUseMaterial: boolean;
          iEdgeNumberFontSize: integer;
          bNorishiroReverse: boolean;
          bEdgeIdReverse: boolean;
          bEnableLineAlpha: boolean;
          dTextureLineAlpha: single;
          bCullEdge: boolean;
          iPageType: integer;
          dPageMarginSide: single;
          dPageMarginTop: single;
          bDrawWhiteBkLine: boolean;
      end;
  end;


implementation


end.

