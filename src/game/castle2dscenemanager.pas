{
  Copyright 2014-2014 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Scene manager (T2DSceneManager) and scene (T2DScene) best suited for 2D worlds. }
unit Castle2DSceneManager;

interface

uses Classes,
  CastleScene, CastleSceneManager, CastleUIControls, CastleCameras;

type
  { Scene manager best suited for 2D worlds.
    Features:
    @unorderedList(
      @item(By default creates camera looking down in -Z, good when your world spans in XY plane.)
      @item(Sets 2D projection (regardless of viewpoints defined in MainScene).)
      @item(Sets RenderStyle = rs2D by default, which makes it possible to place the scene manager rendering in the middle of other 2D controls (for example, over some 2D background and before some 2D buttons.))
      @item(Sets Tranparennt = @true by default, which means that background underneath will be visible. Useful for 2D games where you usually have an image or another background underneath, like TCastleImage or TCastleSimpleBackground.)
    ) }
  T2DSceneManager = class(TCastleSceneManager)
  protected
    procedure ApplyProjection; override;
  public
    property RenderStyle default rs2D;
    constructor Create(AOwner: TComponent); override;
    function CreateDefaultCamera(AOwner: TComponent): TCamera; override;
  end;

  { Scene best suited for 2D models. Sets BlendingSort := bs2D,
    good when your transparent objects have proper order along the Z axis
    (useful e.g. for Spine animations). }
  T2DScene = class(TCastleScene)
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

uses CastleVectors, CastleGLUtils;

{ T2DSceneManager -------------------------------------------------------- }

constructor T2DSceneManager.Create(AOwner: TComponent);
begin
  inherited;
  RenderStyle := rs2D;
  Transparent := true;
end;

function T2DSceneManager.CreateDefaultCamera(AOwner: TComponent): TCamera;
var
  UCamera: TUniversalCamera;
begin
  UCamera := TUniversalCamera.Create(AOwner);
  UCamera.Input := [];
  UCamera.NavigationType := ntExamine;
  UCamera.SetInitialView({ pos } Vector3Single(0, 0, 0),
    { dir } Vector3Single(0, 0, -1), { up } Vector3Single(0, 1, 0), false);
  UCamera.GoToInitial;
  UCamera.Radius := 0.01; { will not be used for anything, but set to something sensible just in case }
  Result := UCamera;
end;

procedure T2DSceneManager.ApplyProjection;
begin
  if Camera = nil then
    Camera := CreateDefaultCamera(Self);

  FPerspectiveView := false;
  { default FOrthoViewDimensions, when not OrthoViewpoint }
  FOrthoViewDimensions[0] := 0;
  FOrthoViewDimensions[1] := 0;
  FOrthoViewDimensions[2] := ContainerWidth;
  FOrthoViewDimensions[3] := ContainerHeight;
  FProjectionNear := -1;
  FProjectionFar := 1;
  FProjectionFarFinite := FProjectionFar;

  Camera.ProjectionMatrix := OrthoProjection(
    { Beware: order of OrthoViewpoint.fieldOfView and FOrthoViewDimensions
      is different than typical OpenGL and our OrthoProjection params. }
    FOrthoViewDimensions[0],
    FOrthoViewDimensions[2],
    FOrthoViewDimensions[1],
    FOrthoViewDimensions[3],
    FProjectionNear, FProjectionFar);
end;

{ T2DScene --------------------------------------------------------------- }

constructor T2DScene.Create(AOwner: TComponent);
begin
  inherited;
  Attributes.BlendingSort := bs2D;
end;

end.
