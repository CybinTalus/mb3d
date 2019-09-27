(*
  HeightMapGenerator for MB3D
  Copyright (C) 2016-2019 Andreas Maschke

  This is free software; you can redistribute it and/or modify it under the terms of the GNU Lesser
  General Public License as published by the Free Software Foundation; either version 2.1 of the
  License, or (at your option) any later version.

  This software is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
  even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
  Lesser General Public License for more details.
  You should have received a copy of the GNU Lesser General Public License along with this software;
  if not, write to the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
  02110-1301 USA, or see the FSF site: http://www.fsf.org.
*)
unit PNMReader;

interface

uses
  SysUtils, Classes, Windows;

type
  TPGM16Reader = class
  private
    FBuffer: PWord;
    FWidth, FHeight: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LoadFromFile( const Filename: String);
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Buffer: PWord read FBuffer;
  end;

implementation

constructor TPGM16Reader.Create;
begin
  inherited;
  FBuffer := nil;
end;

destructor TPGM16Reader.Destroy;
begin
  if FBuffer <> nil then
    FreeMem( FBuffer );
end;

procedure TPGM16Reader.LoadFromFile( const Filename: String);
var
  Reader: TStreamReader;
  Line: String;
  MaxValue: Integer;
  I, J: Integer;
  Lst: TStringList;
  CurrPGMBuffer: PWord;
begin
  Reader := TStreamReader.Create( Filename, TEncoding.ANSI);
  try
    Line := Trim( Reader.ReadLine );
    if Line <> 'P2' then
      raise Exception.Create('Unexpected Header <'+Line+'>');
    Line := Trim( Reader.ReadLine );
    if ( Length(Line) > 0 ) and ( Line[1] = '#' ) then // ignore comment
      Line := Trim( Reader.ReadLine );
     Lst := TStringList.Create;
     try
       I := Pos(' ', Line );
       FWidth := StrToInt( Copy( Line, 1, I - 1 ) );
       FHeight := StrToInt( Copy( Line, I + 1, Length(Line) - I ) );
       if ( FWidth < 1 ) or ( FHeight < 1 ) then
         raise Exception.Create('Invalid Size <'+Line+'>');
       MaxValue := StrToInt( Trim( Reader.ReadLine ) );
       if MaxValue < 1 then
         raise Exception.Create('Invalid Depth <'+IntToStr(MaxValue)+'>');
       GetMem( FBuffer, FWidth * FHeight * SizeOf( Word ) );
       Lst.Delimiter := ' ';
       CurrPGMBuffer := FBuffer;
       for I:=0 to FHeight - 1 do begin
         Lst.DelimitedText := Trim( Reader.ReadLine );
         if Lst.Count <> FWidth then 
           raise Exception.Create('Invalid Line <'+IntToStr(I)+'>: Found <'+IntToStr(Lst.Count)+' items, expected <'+IntToStr(FWidth));
          for J := 0 to Width - 1 do begin
            CurrPGMBuffer^ := Word( StrToInt( Lst[J] ) );
            CurrPGMBuffer := PWord( Longint( CurrPGMBuffer ) + SizeOf( Word ) );
          end;
       end;
     finally
       Lst.Free;
     end;
  finally
    Reader.Free;
  end;
end;

end.
