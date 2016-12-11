program pdoconvert;
{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, cmem,
  {$ENDIF}
  sysutils, classes, crc,
  utils,
  pdo_v2_parser, pdo_v2, pdo2obj;

function optSet(const c: char): boolean;
begin
  result := (Paramcount > 1) and (Pos(c, ParamStr(2)) <> 0)
end;

procedure ExportObj(const name: string; const pdo: TPdoV2Document);
var
  opt: TObjExportOptions;
begin
  writeln('exporting obj: ', name);
  opt.normalize := true;
  opt.flip_v_coordinate := false;
  WriteObj(pdo, name, opt);
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
          ExportObj(fname + '.obj', parser.GetDocument);
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

