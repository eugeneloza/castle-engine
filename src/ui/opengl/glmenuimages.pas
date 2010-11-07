{ -*- buffer-read-only: t -*- }

{ Unit automatically generated by image_to_pas tool,
  to embed images in Pascal source code.
  @exclude (Exclude this unit from PasDoc documentation.) }
unit GLMenuImages;

interface

uses Images;

var
  Slider_base: TRGBImage;

var
  Slider_position: TRGBImage;

implementation

uses SysUtils;

{ Actual image data is included from another file, with a deliberately
  non-Pascal file extension ".image_data". This way ohloh.net will
  not recognize this source code as (uncommented) Pascal source code. }
{$I glmenuimages.image_data}

initialization
  Slider_base := TRGBImage.Create(Slider_baseWidth, Slider_baseHeight);
  Move(Slider_basePixels, Slider_base.RawPixels^, SizeOf(Slider_basePixels));
  Slider_position := TRGBImage.Create(Slider_positionWidth, Slider_positionHeight);
  Move(Slider_positionPixels, Slider_position.RawPixels^, SizeOf(Slider_positionPixels));
finalization
  FreeAndNil(Slider_base);
  FreeAndNil(Slider_position);
end.