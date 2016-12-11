unit utils;

{$mode objfpc}{$H+}

interface

uses classes, sysutils;

procedure WriteTga(const filename: string; const data: pbyte; const width, height, data_length: integer);
procedure PgmSave(const fname: string; p: pbyte; w, h: integer);
procedure PnmSave(const fname: string; const p: pbyte; const w, h: integer);
function clip3(const a, b, c: single): single;
function clip3(const a, b, c: integer): integer;
function GetMsecs: longword;
function Scan(const s: string; const fmt : string; const Pointers : array of Pointer) : Integer;

implementation

uses
  sysconst; //for custom sscanf

procedure WriteTga(const filename: string; const data: pbyte; const width, height, data_length: integer);
const
  HeaderComment = 'Pdo tools';
var
  f: file;
  stream: TMemoryStream;
begin
  stream := TMemoryStream.Create();
  stream.WriteByte(Length(HeaderComment)); //id field length
  stream.WriteByte (0);  //color map type
  stream.WriteByte (2);  //image type: 2 = uncompressed true-color image
  //5B color map specification
  stream.WriteDWord(0);  //2B origin, 2B length
  stream.WriteByte (0);  //1B Color Map Entry Size.
  //10B image specification
  stream.WriteDWord(0);      //X-origin, Y-origin
  stream.WriteWord (width);  //width in pixels
  stream.WriteWord (height); //height in pixels
  stream.WriteByte (24);     //bits per pixel
  stream.WriteByte ($20);    //image descriptor
  stream.Write(HeaderComment, Length(HeaderComment));

  AssignFile(f, filename);
  Rewrite(f, 1);
  blockwrite(f, stream.Memory^, stream.Size);
  blockwrite(f, data^, data_length);
  CloseFile(f);
  stream.Free;
end;

procedure PgmSave(const fname: string; p: pbyte; w, h: integer);
var
  f: file;
  c: PChar;
Begin
  c := PChar(format('P5'#10'%d %d'#10'255'#10, [w, h]));
  AssignFile (f, fname);
  Rewrite (f, 1);
  BlockWrite (f, c^, strlen(c));
  BlockWrite (f, p^, w * h);
  CloseFile (f);
end;

procedure PnmSave(const fname: string; const p: pbyte; const w, h: integer);
var
  f: file;
  c: PChar;
Begin
  c := PChar(format('P6'#10'%d %d'#10'255'#10, [w, h]));
  AssignFile (f, fname);
  Rewrite (f, 1);
  BlockWrite (f, c^, strlen(c));
  BlockWrite (f, p^, w * h * 3);
  CloseFile (f);
end;


function clip3(const a, b, c: single): single;
begin
  if b < a then begin
    result := a;
  end
  else if b > c then begin
    result := c;
  end
  else result := b;
end;

function clip3(const a, b, c: integer): integer;
begin
  if b < a then
    result := a
  else if b > c then
    result := c
  else result := b;
end;

function GetMsecs: longword;
var
  h, m, s, ms: word;
begin
  DecodeTime (sysutils.Time(), h, m, s, ms);
  Result := (h * 3600*1000 + m * 60*1000 + s * 1000 + ms);
end;


function Scan(const s: string; const fmt : string; const Pointers : array of Pointer) : Integer;
var
  i,j,n,m : SizeInt;
  s1      : string;

function GetInt(unsigned : boolean=false) : Integer;
  begin
    s1 := '';
    while (Length(s) > n) and (s[n] = ' ') do
      inc(n);
    { read sign }
    if (Length(s)>= n) and (s[n] in ['+', '-']) then
      begin
        { don't accept - when reading unsigned }
        if unsigned and (s[n]='-') then
          begin
            result:=length(s1);
            exit;
          end
        else
          begin
            s1:=s1+s[n];
            inc(n);
          end;
      end;
    { read numbers }
    while (Length(s) >= n) and
          (s[n] in ['0'..'9']) do
      begin
        s1 := s1+s[n];
        inc(n);
      end;
    Result := Length(s1);
  end;


function GetFloat : Integer;
  begin
    s1 := '';
    while (Length(s) > n) and (s[n] = ' ')  do
      inc(n);
    while (Length(s) >= n) and
          (s[n] in ['0'..'9', '+', '-', FormatSettings.DecimalSeparator, 'e', 'E']) do
      begin
        s1 := s1+s[n];
        inc(n);
      end;
    Result := Length(s1);
  end;


function GetString : Integer;
  begin
    s1 := '';
    while (Length(s) > n) and (s[n] = ' ') do
      inc(n);
    while (Length(s) >= n) and (s[n] <> ' ')do
      begin
        s1 := s1+s[n];
        inc(n);
      end;
    Result := Length(s1);
  end;


function ScanStr(c : Char) : Boolean;
  begin
    while (Length(s) > n) and (s[n] <> c) do
      inc(n);
    inc(n);
    If (n <= Length(s)) then
      Result := True
    else
      Result := False;
  end;


function GetFmt : Integer;
  begin
    Result := -1;
    while true do
      begin

        while (Length(fmt) > m) and (fmt[m] = ' ') do
          inc(m);

        if (m >= Length(fmt)) then
          break;

        if (fmt[m] = '%') then
          begin
            inc(m);
            case fmt[m] of
              'd':
                Result:=vtInteger;
              'f':
                Result:=vtExtended;
              's':
                Result:=vtString;
              'c':
                Result:=vtChar;
              'b':
                Result:=vtBoolean;
              else
                raise EFormatError.CreateFmt(SInvalidFormat,[fmt]);
            end;
            inc(m);
            break;
          end;

        if not(ScanStr(fmt[m])) then
          break;
        inc(m);
      end;
  end;


begin
  n := 1;
  m := 1;
  Result := 0;

  for i:=0 to High(Pointers) do
    begin
      j := GetFmt;
      case j of
        vtInteger :
          begin
            if GetInt>0 then
              begin
                pLongint(Pointers[i])^:=StrToInt(s1);
                inc(Result);
              end
            else
              break;

          end;

        vtBoolean :
          begin
            if GetInt>0 then
              begin
                Assert((s1 = '0') or (s1 = '1'));
                PBoolean(Pointers[i])^:= (s1 = '1');
                inc(Result);
              end
            else
              break;

          end;

        vtchar :
          begin
            if Length(s)>n then
              begin
                pchar(Pointers[i])^:=s[n];
                inc(n);
                inc(Result);
              end
            else
              break;

          end;

        vtExtended :
          begin
            if GetFloat>0 then
              begin
                PSingle(Pointers[i])^:=StrToFloat(s1);
                inc(Result);
              end
            else
              break;
          end;

        vtString :
          begin
            if GetString > 0 then
              begin
                pansistring(Pointers[i])^:=s1;
                inc(Result);
              end
            else
              break;
          end;
        else
          break;
      end;
    end;
 end;

end.

