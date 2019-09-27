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
unit HeightMapGenPreview;

interface

uses
  SysUtils, Classes, Windows, dglOpenGL, Vcl.Graphics, VertexList, VectorMath,
  OpenGLPreviewUtil, ShaderUtil;

type
  TOpenGLHelper = class( TBaseOpenGLHelper )
  private
    FShader : TShader;
    procedure SetupLighting;
    procedure AfterInitGL; override;
    procedure ApplicationEventsIdle( Sender: TObject; var Done: Boolean ); override;
    procedure SaveAsPGM( const  Width, Height: Integer; const DepthBuffer: PGLfloat; const DepthMin, DepthMax: GLfloat; const Filename: String );
    procedure SaveAsPNG( const  Width, Height: Integer; const DepthBuffer: PGLfloat; const DepthMin, DepthMax: GLfloat; const Filename: String );
  public
    constructor Create(const Canvas: TCanvas);
    procedure UpdateMesh( const FacesList: TFacesList ); override;
    procedure SaveHeightMap( const Left, Top, Width, Height: Integer; const Filename: String );
  end;

const
  DFLT_SCALE = 0.5;

implementation

uses
  Forms, Math, DateUtils, PNMWriter, FileHandling;

const
  WindowTitle = 'HeightMap Generator Preview';

{ ------------------------------ TOpenGLHelper ------------------------------- }
constructor TOpenGLHelper.Create(const Canvas: TCanvas);
begin
  inherited Create( Canvas );
  FFOV := 10;
  FScale := DFLT_SCALE;
end;


procedure TOpenGLHelper.AfterInitGL;
const
  FragmentShader: String =
    'float near = 1.0;'#10 +
    'float far  = 36.0;'#10 +
    #10 +
    'float linearizeDepth(float depth) {'#10 +
    '  return (2.0 * near * far) / (far + near - depth * (far - near));'#10 +
    '}'#10 +
    'void main() {'#10 +
    '  float depth = linearizeDepth(gl_FragCoord.z)/16.0;'#10 +
    '  gl_FragColor = vec4(1.0-vec3(depth), 1.0f);'#10 +
    '}'#10;
begin
  FShader := TShader.Create( FragmentShader );
end;

procedure TOpenGLHelper.ApplicationEventsIdle(Sender: TObject; var Done: Boolean);
const
  ZOffset: Double = -7.0;
var
  Error, I : LongInt;
  X, Y, Z: Double;

  V: TPS3Vector;
  Face: TPFace;
  Scl: Double;
begin
  if FRC = 0 then Exit;
  Done := False;

  glClearColor(0,0,0,0);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

  DrawBackground();

  glLoadIdentity;
  glTranslatef( FPosition.X,  FPosition.Y,  ZOffset);
  glRotatef( FAngle.X, 0.0, 1.0, 0.0);
  glRotatef( - FAngle.Y, 1.0, 0.0, 1.0);
  Scl := FScale * 3.0/FMaxObjectSize;
  glScalef(Scl, Scl, Scl);
  glTranslatef( 0.0,  0.0,  FPosition.Z);

  glDisable(GL_LIGHTING);

  if FFaces <> nil then begin
    glVertexPointer( 3, GL_FLOAT, SizeOf(TGLVertex), FVertices);
    if FNormals <> nil then begin
      glEnableClientState( GL_NORMAL_ARRAY );
      glNormalPointer( GL_FLOAT, SizeOf(TGLVertex), FNormals);
    end;

    SetupLighting;
    glShadeModel(GL_SMOOTH);
//    glColor3f(FMeshAppearance.SurfaceColor.X, FMeshAppearance.SurfaceColor.Y, FMeshAppearance.SurfaceColor.Z);
    glDrawElements( GL_TRIANGLES, FFaceCount * 3, GL_UNSIGNED_INT, FFaces );
  end;

  //Error Handler
  Error := glgetError;
  if Error <> GL_NO_ERROR then begin
    if Assigned(FSetWindowCaptionEvent) then
      FSetWindowCaptionEvent( gluErrorString(Error) );
    Done := True;
    FlashWindow(FCanvas.Handle, True)
  end;
  //Frame Counter
  Inc(FFrames);
  if (GetTickCount - FStartTick >= 500) and (FFrames >= 10) and Assigned(FSetWindowCaptionEvent) then begin
    FSetWindowCaptionEvent( Format('%s [%f FPS, %d Vertices, %d Faces]', [WindowTitle, FFrames/(GetTickCount - FStartTick)*1000, FVerticesCount, FFaceCount]));
    FFrames := 0;
    FStartTick := GetTickCount;
  end;
  SwapBuffers(FCanvas.Handle);
  Sleep(1);
end;

procedure TOpenGLHelper.UpdateMesh(const FacesList: TFacesList);
var
  T0, T00: Int64;
  I: Integer;
  Key: String;
  GLVertices, GLVertex: TPGLVertex;
  GLNormals, GLNormal: TPGLVertex;
  GLEdges, GLEdge: TPGLEdge;
  GLFaces, GLFace: TPGLFace;
  EdgesList: TStringList;
  EdgeCount: Integer;
  Vertex: TPS3Vector;
  Normals: TPS3VectorList;

  procedure AddVertex(const Idx: Integer);
  var
    Vertex: TPS3Vector;
  begin
    Vertex := FacesList.GetVertex(Idx);
    if Vertex^.X < FSizeMin.X then
      FSizeMin.X := Vertex^.X
    else if Vertex^.X > FSizeMax.X then
      FSizeMax.X := Vertex^.X;
    if Vertex^.Y < FSizeMin.Y then
      FSizeMin.Y := Vertex^.Y
    else if Vertex^.Y > FSizeMax.Y then
      FSizeMax.Y := Vertex^.Y;
    if Vertex^.Z < FSizeMin.Z then
      FSizeMin.Z := Vertex^.Z
    else if Vertex^.Z > FSizeMax.Z then
      FSizeMax.Z := Vertex^.Z;
    GLVertex^.X := Vertex^.X;
    GLVertex^.Y := -Vertex^.Y;
    GLVertex^.Z := -Vertex^.Z;
    GLVertex := Pointer(Longint(GLVertex)+SizeOf(TGLVertex));
  end;

  procedure AddNormal(const Idx: Integer);
  var
    Vertex: TPS3Vector;
  begin
    Vertex := Normals.GetVertex(Idx);
    GLNormal^.X := Vertex^.X;
    GLNormal^.Y := Vertex^.Y;
    GLNormal^.Z := -Vertex^.Z;
    GLNormal := Pointer(Longint(GLNormal)+SizeOf(TGLVertex));
  end;

  procedure AddFace(const Idx: Integer);
  var
    Face: TPFace;
  begin
    Face := FacesList.GetFace(Idx);
    GLFace^.V1 := Face^.Vertex1;
    GLFace^.V2 := Face^.Vertex2;
    GLFace^.V3 := Face^.Vertex3;
    GLFace := Pointer(Longint(GLFace)+SizeOf(TGLFace));
  end;

  procedure AddEdgeFromList(const Idx: Integer);
  var
    P: Integer;
    Key: String;
  begin
    Key := EdgesList[I];
    P := Pos('#', Key);
    GLEdge^.V1 := StrToInt(Copy(Key, 1, P - 1));
    GLEdge^.V2 := StrToInt(Copy(Key, P+1, Length(Key) - P));
    GLEdge := Pointer(Longint(GLEdge)+SizeOf(TGLEdge));
  end;

  procedure AddEdgesToList(const Idx: Integer);
  var
    Face: TPFace;
(*
    procedure AddEdge(const V1, V2: Integer);
    var
      Key: String;
    begin
      if V1 < V2 then
        Key := IntToStr(V1)+'#'+IntToStr(V2)
      else
        Key := IntToStr(V2)+'#'+IntToStr(V1);
      if EdgesList.IndexOf(Key) < 0 then
        EdgesList.Add(Key);
    end;
*)
    procedure FastAddEdge(const V1, V2: Integer);
    var
      Key: String;
    begin
      Key := IntToStr(V1)+'#'+IntToStr(V2);
      EdgesList.Add(Key);
    end;

  begin
    Face := FacesList.GetFace(Idx);
    FastAddEdge(Face^.Vertex1, Face^.Vertex2);
    if (EdgesList.Count mod 2) = 0 then
      FastAddEdge(Face^.Vertex2, Face^.Vertex3)
    else
      FastAddEdge(Face^.Vertex3, Face^.Vertex1);
(*
    AddEdge(Face^.Vertex1, Face^.Vertex2);
    AddEdge(Face^.Vertex2, Face^.Vertex3);
    AddEdge(Face^.Vertex3, Face^.Vertex1);
    *)
  end;

begin
  T0 := DateUtils.MilliSecondsBetween(Now, 0);
  T00 := T0;

  // TODO create data (e.g. edges) only on demand ?
  FreeVertices;
  if FacesList.Count > 0 then begin
    EdgesList := TStringList.Create;
    try
      EdgesList.Duplicates := dupAccept;
      EdgesList.Sorted := False;
      for I := 0 to FacesList.Count - 1 do
        AddEdgesToList(I);
      EdgesList.Sorted := True;

      EdgeCount := EdgesList.Count;
    ShowDebugInfo('OpenGL.AddEdgesPh1('+IntToStr(EdgeCount)+')', T0);
    T0 := DateUtils.MilliSecondsBetween(Now, 0);
      GetMem(GLEdges, EdgeCount * SizeOf(TGLEdge));
      try
        GLEdge := GLEdges;
        for I := 0 to EdgeCount - 1 do
          AddEdgeFromList(I);
      except
        FreeMem(GLEdges);
        raise;
      end;
    finally
      EdgesList.Free;
    end;
    ShowDebugInfo('OpenGL.AddEdgesPh2', T0);
    T0 := DateUtils.MilliSecondsBetween(Now, 0);

    try
      GetMem(GLVertices, FacesList.VertexCount * SizeOf(TGLVertex));
      try
        GetMem(GLFaces, FacesList.Count * Sizeof(TGLFace));
        try
          GLVertex := GLVertices;

          Vertex := FacesList.GetVertex(0);
          FSizeMin.X := Vertex^.X;
          FSizeMax.X := FSizeMin.X;
          FSizeMin.Y := Vertex^.Y;
          FSizeMax.Y := FSizeMin.Y;
          FSizeMin.Z := Vertex^.Z;
          FSizeMax.Z := FSizeMin.Z;
          for I := 0 to FacesList.VertexCount - 1 do
            AddVertex(I);
  ShowDebugInfo('OpenGL.AddVertices', T0);
  T0 := DateUtils.MilliSecondsBetween(Now, 0);

          FMaxObjectSize := Max(FSizeMax.X - FSizeMin.X, Max(FSizeMax.Y - FSizeMin.Y, FSizeMax.Z - FSizeMin.Z ));
          GLFace := GLFaces;
          for I := 0 to FacesList.Count - 1 do
            AddFace(I);
  ShowDebugInfo('OpenGL.AddFaces', T0);
  T0 := DateUtils.MilliSecondsBetween(Now, 0);

          FFaceCount := FacesList.Count;
          FVerticesCount := FacesList.VertexCount;
          FEdgeCount := EdgeCount;
          FVertices := GLVertices;

          try
            GetMem(GLNormals, FVerticesCount * SizeOf(TGLVertex));
            try
               GLNormal := GLNormals;
               Normals := FacesList.CalculateVertexNormals;
               try
                 if Normals.Count <> FVerticesCount then
                   raise Exception.Create('Invalid normals');
                 for I := 0 to Normals.Count - 1 do
                   AddNormal(I);
               finally
                 Normals.Free;
               end;
            except
              FreeMem(GLNormals);
              raise;
            end;
          except
            GLNormals := nil;
            // Hide error as normals are optional
          end;
          FNormals := GLNormals;


          FFaces := GLFaces;
          FEdges := GLEdges;
        except
          FreeMem(GLFaces);
          raise;
        end;
      except
        FreeMem(GLVertices);
        raise;
      end;
    except
      FreeMem(GLEdges);
      raise;
    end;
  end;
  ShowDebugInfo('OpenGL.AddNormals', T0);
  ShowDebugInfo('OpenGL.TOTAL', T00);
end;

procedure TOpenGLHelper.SetupLighting;
begin
  glDisable(GL_LIGHTING);
  FShader.Use;
end;

procedure TOpenGLHelper.SaveHeightMap(const Left, Top, Width, Height: Integer; const Filename: String);
const
  zNear = 1.0;
  zFar = 100.0;
var
  I, ValueCount, BufSize: Integer;
  DepthBuffer: Pointer;
  CurrDepth: PGLfloat;
  DepthMin, DepthMax: GLfloat;
  FinalDepthMin, FinalDepthMax: GLfloat;
begin
  ValueCount := Width  * Height;
  BufSize := ValueCount * SizeOf( GLfloat );
  GetMem( DepthBuffer, BufSize );
  try
    glReadPixels( Left, Top, Width, Height, GL_DEPTH_COMPONENT, GL_FLOAT, DepthBuffer );
    DepthMin := 1.0;
    DepthMax := 0.0;
    for I := 0 to ValueCount - 1 do begin
      CurrDepth := PGLfloat( Longint( DepthBuffer ) + Longint( I * SizeOf( GLfloat ) ) );
      CurrDepth^ := ( 2.0 * zNear ) / ( zFar + zNear - CurrDepth^ * ( zFar - zNear ) );
      if CurrDepth^ < DepthMin  then
        DepthMin := CurrDepth^
      else if ( CurrDepth^ > DepthMax ) and ( CurrDepth^ < 0.99 ) then
        DepthMax := CurrDepth^;
    end;

    FinalDepthMin := 1.0;
    FinalDepthMax := 0.0;
    for I := 0 to ValueCount - 1 do begin
      CurrDepth := PGLfloat( Longint( DepthBuffer ) + Longint( I * SizeOf( GLfloat ) ) );
      if CurrDepth^ > DepthMax then
        CurrDepth^ := 0
      else
        CurrDepth^ := DepthMax - CurrDepth^;
      if  CurrDepth^ < FinalDepthMin  then
        FinalDepthMin := CurrDepth^
      else if  CurrDepth^ > FinalDepthMax then
        FinalDepthMax := CurrDepth^;
    end;

    OutputDebugString(PChar('Depth: ' + FloatToStr(FinalDepthMin) + '...' + FloatToStr(FinalDepthMax)));

    if AnsiLowerCase( ExtractFileExt( Filename ) ) = '.pgm' then
      SaveAsPGM(  Width, Height, DepthBuffer, FinalDepthMin, FinalDepthMax, Filename)
    else
      SaveAsPNG(  Width, Height, DepthBuffer, FinalDepthMin, FinalDepthMax, Filename);
  finally
    FreeMem( DepthBuffer );
  end;
end;

procedure TOpenGLHelper.SaveAsPGM( const  Width, Height: Integer; const DepthBuffer: PGLfloat; const DepthMin, DepthMax: GLfloat; const Filename: String );
var
  I, J: Integer;
  PGMBuffer, CurrPGMBuffer: PWord;
  CurrDepthBuffer: PGLfloat;
  DepthVal, Delta: Double;

  function TransformValue( const Value: GLfloat ): GLfloat;
  begin
    Result := ( Value - DepthMin ) / Delta;
  end;

begin
  Delta := DepthMax - DepthMin;
  GetMem( PGMBuffer, Width * Height * SizeOf( Word ) );
  try
    CurrPGMBuffer := PGMBuffer;
    for I := 0 to Height - 1 do begin
      CurrDepthBuffer := PGLfloat( Longint(DepthBuffer) + ( Height - I - 1 ) * Width * SizeOf( GLfloat ) );
      for J := 0 to Width - 1 do begin
        DepthVal := Min( Max( 0.0, TransformValue( CurrDepthBuffer^ ) ), 1.0 );
        CurrPGMBuffer^ := Word( Round( DepthVal * 65535 ) );
        Inc( CurrDepthBuffer );
        CurrPGMBuffer := PWord( Longint( CurrPGMBuffer ) + SizeOf( Word ) );
      end;
    end;
    with TPGM16Writer.Create do try
      SaveToFile( PGMBuffer, Width, Height, Filename );
    finally
      Free;
    end;
  finally
    FreeMem( PGMBuffer );
  end;
end;

procedure TOpenGLHelper.SaveAsPNG( const  Width, Height: Integer; const DepthBuffer: PGLfloat; const DepthMin, DepthMax: GLfloat; const Filename: String );
var
  I, J: Integer;
  CurrDepthBuffer: PGLfloat;
  DepthVal, Delta: Double;
  BMP: TBitmap;
  PB: PByte;

  function TransformValue( const Value: GLfloat ): GLfloat;
  begin
    Result := ( Value - DepthMin ) / Delta;
  end;

begin
  BMP := TBitmap.Create;
  try
    BMP.PixelFormat := pf8Bit;
    BMP.SetSize( Width, Height );
    Make8bitGreyscalePalette(Bmp);

    Delta := DepthMax - DepthMin;
    for I := 0 to Height - 1 do begin
      CurrDepthBuffer := PGLfloat( Longint(DepthBuffer) + ( Height - I - 1 ) * Width * SizeOf( GLfloat ) );
      PB := BMP.ScanLine[ I ];
      for J := 0 to Width - 1 do begin
        DepthVal := Min( Max( 0.0, TransformValue( CurrDepthBuffer^ ) ), 1.0 );
        Inc( CurrDepthBuffer );
        PB^:=Byte(Round(DepthVal*255.0));
        Inc(PB);
      end;
    end;
    SavePNG( Filename, BMP, False );
  finally
    BMP.Free;
  end;
end;


end.


