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
unit ShaderUtil;

interface

uses
  SysUtils, Classes, dglOpenGL;


// from https://github.com/neslib/DelphiLearnOpenGL/blob/master/Tutorials/Common/Sample.Classes.pas
type
  { Encapsulates an OpenGL shader program consisting of a vertex shader and
    fragment shader. Implemented in the TShader class. }
  IShader = interface
  ['{6389D101-5FD2-4AEA-817A-A4AF21C7189D}']
    {$REGION 'Internal Declarations'}
    function _GetHandle: GLuint;
    {$ENDREGION 'Internal Declarations'}

    { Uses (activates) the shader for rendering }
    procedure Use;

    { Retrieves the location of a "uniform" (global variable) in the shader.
      Parameters:
        AName: the name of the uniform to retrieve
      Returns:
        The location of the uniform.
      Raises an exception if the AName is not found in the shader. }
    function GetUniformLocation(const AName: RawByteString): Integer;
    function GetUniformLocationUnicode(const AName: String): Integer;

    { Low level OpenGL handle of the shader. }
    property Handle: GLuint read _GetHandle;
  end;

type
  { Implements IShader }
  TShader = class(TInterfacedObject, IShader)
  {$REGION 'Internal Declarations'}
  private
    FProgram: GLuint;
  private
    class function CreateShader(const AShaderCode: String; const AShaderType: GLenum): GLuint; static;
  protected
    { IShader }
    function _GetHandle: GLuint;
    function GetUniformLocation(const AName: RawByteString): Integer;
    function GetUniformLocationUnicode(const AName: String): Integer;
  {$ENDREGION 'Internal Declarations'}
  public
    constructor Create(const AVertexShaderCode, AFragmentShaderCode: String); overload;
    constructor Create(const AFragmentShaderCode: String); overload;
    destructor Destroy; override;
    procedure Use;
  end;

implementation

const
  R_TRUE = 1;
  R_FALSE = 0;

{$IFDEF DEBUG}
procedure glErrorCheck;
var
  Error: GLenum;
begin
  Error := glGetError;
  if (Error <> GL_NO_ERROR) then
    raise Exception.CreateFmt('OpenGL Error: $%.4x', [Error]);
end;
{$ELSE}
procedure glErrorCheck; inline;
begin
  { Nothing }
end;
{$ENDIF}

constructor TShader.Create(const AVertexShaderCode, AFragmentShaderCode: String);
var
  Status, LogLength: GLint;
  VertexShader, FragmentShader: GLuint;
  Log: TBytes;
  Msg: String;
begin
  inherited Create;
  FragmentShader := 0;
  VertexShader := CreateShader(AVertexShaderCode, GL_VERTEX_SHADER);
  try
    FragmentShader := CreateShader(AFragmentShaderCode, GL_FRAGMENT_SHADER);
    FProgram := glCreateProgram;

    glAttachShader(FProgram, VertexShader);
    glErrorCheck;

    glAttachShader(FProgram, FragmentShader);
    glErrorCheck;

    glLinkProgram(FProgram);
    glGetProgramiv(FProgram, GL_LINK_STATUS, @Status);

    if (Status <> R_TRUE) then
    begin
      glGetProgramiv(FProgram, GL_INFO_LOG_LENGTH, @LogLength);
      if (LogLength > 0) then
      begin
        SetLength(Log, LogLength);
        glGetProgramInfoLog(FProgram, LogLength, @LogLength, @Log[0]);
        Msg := TEncoding.ANSI.GetString(Log);
        raise Exception.Create(Msg);
      end;
    end;
    glErrorCheck;
  finally
    if (FragmentShader <> 0) then
      glDeleteShader(FragmentShader);

    if (VertexShader <> 0) then
      glDeleteShader(VertexShader);
  end;
end;

constructor TShader.Create(const AFragmentShaderCode: String);
var
  Status, LogLength: GLint;
  FragmentShader: GLuint;
  Log: TBytes;
  Msg: String;
begin
  inherited Create;
  FragmentShader := CreateShader(AFragmentShaderCode, GL_FRAGMENT_SHADER);
  try
    FProgram := glCreateProgram;

    glAttachShader(FProgram, FragmentShader);
    glErrorCheck;

    glLinkProgram(FProgram);
    glGetProgramiv(FProgram, GL_LINK_STATUS, @Status);

    if (Status <> R_TRUE) then
    begin
      glGetProgramiv(FProgram, GL_INFO_LOG_LENGTH, @LogLength);
      if (LogLength > 0) then
      begin
        SetLength(Log, LogLength);
        glGetProgramInfoLog(FProgram, LogLength, @LogLength, @Log[0]);
        Msg := TEncoding.ANSI.GetString(Log);
        raise Exception.Create(Msg);
      end;
    end;
    glErrorCheck;
  finally
    if (FragmentShader <> 0) then
      glDeleteShader(FragmentShader);
  end;
end;

class function TShader.CreateShader(const AShaderCode: String; const AShaderType: GLenum): GLuint;
var
  Source: RawByteString;
  SourcePtr: MarshaledAString;
  Status, LogLength: GLint;
  Log: TBytes;
  Msg: String;
begin
  Result := glCreateShader(AShaderType);
  Assert(Result <> 0);
  glErrorCheck;

  Source := AShaderCode;

  {$IFNDEF MOBILE}
  { Desktop OpenGL doesn't recognize precision specifiers }
  if (AShaderType = GL_FRAGMENT_SHADER) then
    Source :=
      '#define lowp'#10+
      '#define mediump'#10+
      '#define highp'#10+
      Source;
  {$ENDIF}

  SourcePtr := MarshaledAString(Source);
  glShaderSource(Result, 1, @SourcePtr, nil);
  glErrorCheck;

  glCompileShader(Result);
  glErrorCheck;

  Status := R_FALSE;
  glGetShaderiv(Result, GL_COMPILE_STATUS, @Status);
  if (Status <> R_TRUE) then
  begin
    glGetShaderiv(Result, GL_INFO_LOG_LENGTH, @LogLength);
    if (LogLength > 0) then
    begin
      SetLength(Log, LogLength);
      glGetShaderInfoLog(Result, LogLength, @LogLength, @Log[0]);
      Msg := TEncoding.ANSI.GetString(Log);
      raise Exception.Create(Msg);
    end;
  end;
end;

destructor TShader.Destroy;
begin
  glUseProgram(0);
  if (FProgram <> 0) then
    glDeleteProgram(FProgram);
  inherited;
end;

function TShader.GetUniformLocation(const AName: RawByteString): Integer;
begin
  Result := glGetUniformLocation(FProgram, MarshaledAString(AName));
  if (Result < 0) then
    raise Exception.CreateFmt('Uniform "%s" not found in shader', [AName]);
end;

function TShader.GetUniformLocationUnicode(const AName: String): Integer;
begin
  Result := GetUniformLocation(RawByteString(AName));
end;

procedure TShader.Use;
begin
  glUseProgram(FProgram);
end;

function TShader._GetHandle: GLuint;
begin
  Result := FProgram;
end;


end.
