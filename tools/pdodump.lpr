program pdoconvert;
{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, cmem,
  {$ENDIF}
  sysutils, classes, crc,
  utils,
  pdo_v2_parser, pdo_v2,
  pdo2obj, pdo2opf_v2, opf2vector;

function optSet(const c: char): boolean;
begin
  result := (Paramcount > 1) and (Pos(c, ParamStr(2)) <> 0)
end;

procedure ExportObj(const pdo: TPdoV2Document; const name: string);
var
  opt: TObjExportOptions;
begin
  writeln('exporting obj: ', name);
  opt.normalize := true;
  opt.flip_v_coordinate := false;
  WriteObj(pdo, name, opt);
end;

procedure ExportPatterns(const pdo: TPdoV2Document; const name: string);
var
  transform: PdoToOpf2dTransform;
  opt: TVectorExportOptions;
  vec_export: TOpf2dVectorExport;
begin
  transform := PdoToOpf2dTransform.Create(pdo);
  transform.PartsTo2D;

  transform.RasterizeToPngStream(150);
  transform.DumpPng('d:\david\devel\projekty\pdo_v2\source\tools\');

  opt.outlines := true;
  opt.textures := true;
  opt.foldlines := true;
  opt.extended_foldlines := true;
  opt.tabs := true;
  opt.debug_edges := false;
  opt.faces := true;

  vec_export := TOpf2dVectorExport.Create(pdo, transform.GetParts, transform.GetPageSetup);
  vec_export.Export2dParts(name, TvfSvg, opt);
  vec_export.Free;

  transform.Free;
end;


procedure TimedLoad(const parser: TPdoV2Parser);
var
  t: LongWord;
begin
  t := GetMsecs;
  parser.Load;
  t := GetMsecs - t;
  writeln('parsing time: ', (t / 1000):5:2);
end;

procedure TimedProcessData(const parser: TPdoV2Parser);
var
  t: LongWord;
  infile: string;
  fname: string;
begin
  t := GetMsecs;
  infile := ParamStr(1);
  if Paramcount > 1 then begin
      fname := ExtractFilePath(infile);
      if fname <> '' then
          fname += DirectorySeparator;
      if Paramcount > 2 then
          fname += ParamStr(3)
      else
          fname += ExtractFileName(ParamStr(1));

      if optSet('o') then
          ExportObj(parser.GetDocument, fname + '.obj');

      if optSet('s') then
          ExportPatterns(parser.GetDocument, fname + '.svg');
  end;
  t := GetMsecs - t;
  writeln('processing time: ', (t / 1000):5:2);
end;

var
  infile: string;
  pdo: TPdoV2Parser;

begin
  if Paramcount < 1 then begin
      writeln('usage: pdodump file [params] [output name]');
      writeln('params:');
      writeln('  d - dump pdo structure');
      writeln('  o - output obj');
      writeln('specify input file');
      halt;
  end;
  infile := ParamStr(1);
  writeln('file: ', infile);
  if not FileExists(infile) then begin
      writeln('file doesn''t exist!');
      halt;
  end;

  pdo := TPdoV2Parser.Create();
  pdo.OpenFile(infile);
  TimedLoad(pdo);
  TimedProcessData(pdo);
  pdo.Free;
  writeln('done');
end.

