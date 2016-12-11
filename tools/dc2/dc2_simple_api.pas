unit dc2_simple_api;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  zstream;

type
  { TLzEncoder }
  TLzEncoder = class
  private
      _encoded_size: integer;

  public
      constructor Create(const compression_level: byte = 2);
      function EncodeBytesToStream(const src: pbyte; const size: integer; var dest: TMemoryStream): integer;
  end;

implementation

{ TLzEncoder }

constructor TLzEncoder.Create(const compression_level: byte);
begin
  _encoded_size := 0;
end;

function TLzEncoder.EncodeBytesToStream(const src: pbyte; const size: integer; var dest: TMemoryStream): integer;
var
  zs: Tcompressionstream;
begin
  zs := Tcompressionstream.create(cldefault, dest, true);
  zs.WriteBuffer(src^, size);
  zs.Free;
  result := _encoded_size;
end;

end.

