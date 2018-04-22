{
  Copyright 2009-2018 Michalis Kamburelis.
  Parts based on white dune (GPL >= 2):
  Stephen F. White, J. "MUFTI" Scheurich, others.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software.

  Although most of the "Castle Game Engine" is available on terms of LGPL
  (see COPYING.txt in this distribution for detailed info), parts of this unit
  are an exception: they use white dune strict GPL >= 2 code.
  You can redistribute and/or modify *this unit, CastleNURBS.pas, as a whole*
  only under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  If the engine is compiled with CASTLE_ENGINE_LGPL symbol
  (see ../base/castleconf.inc), an alternative "dummy" implementation of
  this unit will be used, that doesn't depend on any GPL code.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Common utilities for NURBS curves and surfaces. }
unit CastleNURBS;

{$I castleconf.inc}

interface

uses SysUtils, CastleUtils, CastleVectors, CastleBoxes;

{ Calculate the tessellation (number of NURBS points generated).
  This follows X3D spec for "an implementation subdividing
  the surface into an equal number of subdivision steps".
  Give value of tessellation field, and count of controlPoints.

  Returned value is for sure > 0 (never exactly 0). }
function ActualTessellation(const Tessellation: Integer;
  const Dimension: Cardinal): Cardinal;

{ Return point on NURBS curve.

  Requires:
  @unorderedList(
    @item PointsCount > 0 (not exactly 0).
    @item Order >= 2 (X3D and VRML 97 spec require this too).
    @item Knot must have exactly PointsCount + Order items.
  )

  Weight will be used only if it has the same length as PointsCount.
  Otherwise, Weight = 1.0 (that is, defining non-rational curve) will be used
  (this follows X3D spec).

  Tangent, if non-nil, will be set to the direction at given point of the
  curve, pointing from the smaller to larger knot values.
  It will be normalized. This can be directly useful to generate
  orientations by X3D NurbsOrientationInterpolator node.

  @groupBegin }
function NurbsCurvePoint(const Points: PVector3Array;
  const PointsCount: Cardinal; const U: Single;
  const Order: Cardinal;
  Knot, Weight: TDoubleList;
  Tangent: PVector3): TVector3;
function NurbsCurvePoint(const Points: TVector3List;
  const U: Single;
  const Order: Cardinal;
  Knot, Weight: TDoubleList;
  Tangent: PVector3): TVector3;
{ @groupEnd }

{ Return point on NURBS surface.

  Requires:
  @unorderedList(
    @item UDimension, VDimension > 0 (not exactly 0).
    @item Points.Count must match UDimension * VDimension.
    @item Order >= 2 (X3D and VRML 97 spec require this too).
    @item Each xKnot must have exactly xDimension + Order items.
  )

  Weight will be used only if it has the same length as PointsCount.
  Otherwise, Weight = 1.0 (that is, defining non-rational curve) will be used
  (this follows X3D spec).

  Normal, if non-nil, will be set to the Normal at given point of the
  surface. It will be normalized. You can use this to pass these normals
  to rendering. Or to generate normals for X3D NurbsSurfaceInterpolator node. }
function NurbsSurfacePoint(const Points: TVector3List;
  const UDimension, VDimension: Cardinal;
  const U, V: Single;
  const UOrder, VOrder: Cardinal;
  UKnot, VKnot, Weight: TDoubleList;
  Normal: PVector3): TVector3;

type
  EInvalidPiecewiseBezierCount = class(Exception);

  { Naming notes: what precisely is called a "uniform" knot vector seems
    to differ in literature / software.
    Blender calls nkPeriodicUniform as "Uniform",
    and nkEndpointUniform as "Endpoint".
    http://en.wiki.mcneel.com/default.aspx/McNeel/NURBSDoc.html
    calls nkEndpointUniform as "Uniform".
    "An introduction to NURBS: with historical perspective"
    (by David F. Rogers) calls nkEndpointUniform "open uniform" and
    nkPeriodicUniform "periodic uniform". }

  { Type of NURBS knot vector to generate. }
  TNurbsKnotKind = (
    { All knot values are evenly spaced, all knots are single.
      This is good for periodic curves. }
    nkPeriodicUniform,

    { Starting and ending knots have Order multiplicity, rest is evenly spaced.
      The curve hits endpoints. }
    nkEndpointUniform,

    { NURBS curve will effectively become a piecewise Bezier curve.
      The Order of NURBS curve will determine the Order of Bezier curve,
      for example NURBS curve with Order = 4 results in a cubic Bezier curve. }
    nkPiecewiseBezier);

{ Calculate a default knot, if Knot doesn't already have required number of items.
  After this, it's guaranteed that Knot.Count is Dimension + Order
  (just as required by NurbsCurvePoint, NurbsSurfacePoint).
  @raises(EInvalidPiecewiseBezierCount When you use nkPiecewiseBezier
    with invalid control points count (Dimension) and Order.) }
procedure NurbsKnotIfNeeded(Knot: TDoubleList;
  const Dimension, Order: Cardinal; const Kind: TNurbsKnotKind);

function NurbsBoundingBox(Point: TVector3List;
  Weight: TDoubleList): TBox3D; overload;
function NurbsBoundingBox(Point: TVector3List;
  Weight: TSingleList): TBox3D; overload;

function NurbsBoundingBox(Point: TVector3List;
  Weight: TDoubleList; const Transform: TMatrix4): TBox3D; overload;
function NurbsBoundingBox(Point: TVector3List;
  Weight: TSingleList; const Transform: TMatrix4): TBox3D; overload;

implementation

function ActualTessellation(const Tessellation: Integer;
  const Dimension: Cardinal): Cardinal;
begin
  if Tessellation > 0 then
    Result := Tessellation else
  if Tessellation = 0 then
    Result := 2 * Dimension else
    Result := Cardinal(-Tessellation) * Dimension;
  Inc(Result);
end;

function NurbsCurvePoint(const Points: TVector3List;
  const U: Single;
  const Order: Cardinal;
  Knot, Weight: TDoubleList;
  Tangent: PVector3): TVector3;
begin
  Result := NurbsCurvePoint(PVector3Array(Points.List), Points.Count,
    U, Order, Knot, Weight, Tangent);
end;

{$ifdef CASTLE_ENGINE_LGPL}

{ Dummy implementations }

function NurbsCurvePoint(const Points: PVector3Array;
  const PointsCount: Cardinal; const U: Single;
  const Order: Cardinal;
  Knot, Weight: TDoubleList;
  Tangent: PVector3): TVector3;
begin
  Result := TVector3.Zero;
end;

function NurbsSurfacePoint(const Points: TVector3List;
  const UDimension, VDimension: Cardinal;
  const U, V: Single;
  const UOrder, VOrder: Cardinal;
  UKnot, VKnot, Weight: TDoubleList;
  Normal: PVector3): TVector3;
begin
  Result := TVector3.Zero;
end;

{$else CASTLE_ENGINE_LGPL}

{ findSpan and BasisFuns is rewritten from white dune's C source code
  (almost identical methods of NodeNurbsCurve and NodeNurbsSurface).
  Also NurbsCurvePoint is based on NodeNurbsCurve::curvePoint.
  Also NurbsSurfacePoint is based on NodeNurbsSurface::surfacePoint.
  Also NurbsUniformKnotIfNeeded is based on NodeNurbsSurface::linearUknot.

  White dune:
  - http://wdune.ourproject.org/
  - J. "MUFTI" Scheurich, Stephen F. White
  - GPL >= 2, so we're free to copy
  - findSpan and BasisFuns were methods in NodeNurbsCurve
    (src/NodeNurbsCurve.cpp) and NodeNurbsSurface.
    *Almost* exactly identical, the only difference: NodeNurbsSurface
    had these two additional lines (safety check, included in my version):
      if ((Right[r+1] + Left[j-r]) == 0)
          return;
}
function FindSpan(const Dimension, Order: LongInt;
  const u: Single; Knot: TDoubleList): LongInt;
var
  NewLow, NewMid, NewHigh, OldLow, OldMid, OldHigh, n: LongInt;
begin
  n := Dimension + Order - 1;

  if u >= Knot[n] then
  begin
    Result := n - Order;
    Exit;
  end;

  NewLow := Order - 1;
  NewHigh := n - Order + 1;

  NewMid := (NewLow + NewHigh) div 2;

  OldLow := NewLow;
  OldHigh := NewHigh;
  OldMid := NewMid;
  while (u < Knot[NewMid]) or (u >= Knot[NewMid+1]) do
  begin
    if u < Knot[NewMid] then
      NewHigh := NewMid else
      NewLow := NewMid;

    NewMid := (NewLow + NewHigh) div 2;

    // emergency abort of loop, otherwise a endless loop can occure
    if (NewLow = OldLow) and (NewHigh = OldHigh) and (NewMid = OldMid) then
      Break;

    OldLow := NewLow;
    OldHigh := NewHigh;
    OldMid := NewMid;
  end;
  Result := NewMid;
end;

procedure BasisFuns(const Span: LongInt; const u: Single; const Order: LongInt;
  Knot, Basis, Deriv: TDoubleList);
var
  Left, Right: TDoubleList;
  j, r: LongInt;
  Saved, dSaved, Temp: Single;
begin
  Left  := TDoubleList.Create; Left .Count := Order;
  Right := TDoubleList.Create; Right.Count := Order;

  Basis[0] := 1.0;
  for j := 1 to  Order - 1 do
  begin
    Left[j] := u - Knot[Span+1-j];
    Right[j] := Knot[Span+j]-u;
    Saved := 0.0;
    dSaved := 0.0;
    for r := 0 to j - 1 do
    begin
      if (Right[r+1] + Left[j-r]) = 0 then
      begin
        { Or we could use try..finally, at a (very very small) speed penalty. }
        FreeAndNil(Left);
        FreeAndNil(Right);
        Exit;
      end;
      Temp := Basis[r] / (Right[r+1] + Left[j-r]);
      Basis[r] := Saved + Right[r+1] * Temp;
      Deriv[r] := dSaved - j * Temp;
      Saved := Left[j-r] * Temp;
      dSaved := j * Temp;
    end;
    Basis[j] := Saved;
    Deriv[j] := dSaved;
  end;

  FreeAndNil(Left);
  FreeAndNil(Right);
end;

function NurbsCurvePoint(const Points: PVector3Array;
  const PointsCount: Cardinal; const U: Single;
  const Order: Cardinal;
  Knot, Weight: TDoubleList;
  Tangent: PVector3): TVector3;
var
  i: Integer;
  w, duw: Single;
  Span: LongInt;
  Basis, Deriv: TDoubleList;
  UseWeight: boolean;
  du: TVector3;
  Index: Cardinal;
begin
  UseWeight := Cardinal(Weight.Count) = PointsCount;

  Basis := TDoubleList.Create; Basis.Count := Order;
  Deriv := TDoubleList.Create; Deriv.Count := Order;

  Span := FindSpan(PointsCount, Order, u, Knot);

  BasisFuns(Span, u, Order, Knot, Basis, Deriv);

  Result := TVector3.Zero;
  du := TVector3.Zero;

  w := 0.0;
  duw := 0.0;

  for i := 0 to Order-1 do
  begin
    Index := Span - Order + 1 + i;
    Result := Result + (Points^[Index] * Basis[i]);
    du := du + (Points^[Index] * Deriv[i]);
    if UseWeight then
    begin
      w := w + (Weight[Index] * Basis[i]);
      duw := duw + (Weight[Index] * Deriv[i]);
    end else
    begin
      w := w + Basis[i];
      duw := duw + Deriv[i];
    end;
  end;

  Result := Result / w;

  if Tangent <> nil then
  begin
    Tangent^ := (du - Result * duw) / w;
    Tangent^.NormalizeMe;
  end;

  FreeAndNil(Basis);
  FreeAndNil(Deriv);
end;

function NurbsSurfacePoint(const Points: TVector3List;
  const UDimension, VDimension: Cardinal;
  const U, V: Single;
  const UOrder, VOrder: Cardinal;
  UKnot, VKnot, Weight: TDoubleList;
  Normal: PVector3): TVector3;
var
  uBasis, vBasis, uDeriv, vDeriv: TDoubleList;
  uSpan, vSpan: LongInt;
  I, J: LongInt;
  uBase, vBase, Index: Cardinal;
  du, dv, un, vn: TVector3;
  w, duw, dvw: Single;
  Gain, duGain, dvGain: Single;
  P: TVector3;
  UseWeight: boolean;
begin
  UseWeight := Weight.Count = Points.Count;

  uBasis := TDoubleList.Create; uBasis.Count := UOrder;
  vBasis := TDoubleList.Create; vBasis.Count := VOrder;
  uDeriv := TDoubleList.Create; uDeriv.Count := UOrder;
  vDeriv := TDoubleList.Create; vDeriv.Count := VOrder;

  uSpan := findSpan(uDimension, uOrder, u, uKnot);
  vSpan := findSpan(vDimension, vOrder, v, vKnot);

  BasisFuns(uSpan, u, uOrder, uKnot, uBasis, uDeriv);
  BasisFuns(vSpan, v, vOrder, vKnot, vBasis, vDeriv);

  uBase := uSpan - uOrder + 1;
  vBase := vSpan - vOrder + 1;

  Index := vBase * uDimension + uBase;
  Result := TVector3.Zero;
  du := TVector3.Zero;
  dv := TVector3.Zero;

  w := 0.0;
  duw := 0.0;
  dvw := 0.0;

  for j := 0 to vOrder -1 do
  begin
    for i := 0 to uOrder - 1 do
    begin
      Gain := uBasis[i] * vBasis[j];
      duGain := uDeriv[i] * vBasis[j];
      dvGain := uBasis[i] * vDeriv[j];

      P := Points.List^[Index];

      Result := Result + (P * Gain);

      du := du + (P * duGain);
      dv := dv + (P * dvGain);
      if UseWeight then
      begin
        w := w + (Weight[Index] * Gain);
        duw := duw + (Weight[Index] * duGain);
        dvw := dvw + (Weight[Index] * dvGain);
      end else
      begin
        w := w + Gain;
        duw := duw + duGain;
        dvw := dvw + dvGain;
      end;
      Inc(Index);
    end;
    Index := Index + (uDimension - uOrder);
  end;

  Result := Result / w;

  if Normal <> nil then
  begin
    un := (du - Result * duw) / w;
    vn := (dv - Result * dvw) / w;
    Normal^ := TVector3.CrossProduct(un, vn);
    Normal^.NormalizeMe;
  end;

  FreeAndNil(uBasis);
  FreeAndNil(vBasis);
  FreeAndNil(uDeriv);
  FreeAndNil(vDeriv);
end;

{$endif CASTLE_ENGINE_LGPL}

procedure NurbsKnotIfNeeded(Knot: TDoubleList;
  const Dimension, Order: Cardinal; const Kind: TNurbsKnotKind);
var
  I, Segments: Integer;
begin
  if Cardinal(Knot.Count) <> Dimension + Order then
  begin
    Knot.Count := Dimension + Order;

    case Kind of
      nkPeriodicUniform:
        begin
          for I := 0 to Knot.Count - 1 do
            Knot.List^[I] := I;
        end;
      nkEndpointUniform:
        begin
          for I := 0 to Order - 1 do
          begin
            Knot.List^[I] := 0;
            Knot.List^[Cardinal(I) + Dimension] := Dimension - Order + 1;
          end;
          for I := Order to Dimension - 1 do
            Knot.List^[I] := I - Order + 1;
          for I := 0 to Dimension + Order - 1 do
            Knot.List^[I] := Knot.List^[I] / (Dimension - Order + 1);
        end;
      nkPiecewiseBezier:
        begin
          { For useful notes on knots, see
            http://www-evasion.imag.fr/~Francois.Faure/doc/inventorMentor/sgi_html/ch08.html
            http://saccade.com/writing/graphics/KnotVectors.pdf

            For Order = 4 (cubic Bezier curve) and 3 segments you want to get
            14 knot values:
              0 0 0 0
                1 1 1
                2 2 2
              3 3 3 3

            Control points count (Dimension) must be "Segments * (Order - 1)  + 1".
            In the example above, we have Dimension = 10,
            and it matches knot count that has Dimension + Order = 14.
          }

          Segments := (Dimension - 1) div (Order - 1);
          if (Dimension - 1) mod (Order - 1) <> 0 then
            raise EInvalidPiecewiseBezierCount.CreateFmt('Invalid NURBS curve control points count (%d) for a piecewise Bezier curve with Order %d',
              [Dimension, Order]);

          for I := 0 to Order - 1 do
          begin
            Knot.List^[I] := 0;
            Knot.List^[Cardinal(I) + Dimension] := Segments;
          end;
          for I := Order to Dimension - 1 do
            Knot.List^[I] := (I - Order) div (Order - 1) + 1;
        end;
      else raise EInternalError.Create('NurbsKnotIfNeeded 594');
    end;

    // Debug:
    // Writeln('Recalculated NURBS knot:');
    // for I := 0 to Knot.Count - 1 do
    //   Writeln(I:4, ' = ', Knot[I]:1:2);
  end;
end;

function NurbsBoundingBox(Point: TVector3List;
  Weight: TDoubleList): TBox3D;
var
  V: PVector3;
  W: Single;
  I: Integer;
begin
  if Weight.Count = Point.Count then
  begin
    if Point.Count = 0 then
      Result := TBox3D.Empty else
    begin
      W := Weight.List^[0];
      if W = 0 then W := 1;

      Result.Data[0] := Point.List^[0] / W;
      Result.Data[1] := Result.Data[0];

      for I := 1 to Point.Count - 1 do
      begin
        V := Point.Ptr(I);
        W := Weight.List^[I];
        if W = 0 then W := 1;

        MinVar(Result.Data[0].Data[0], V^.Data[0] / W);
        MinVar(Result.Data[0].Data[1], V^.Data[1] / W);
        MinVar(Result.Data[0].Data[2], V^.Data[2] / W);

        MaxVar(Result.Data[1].Data[0], V^.Data[0] / W);
        MaxVar(Result.Data[1].Data[1], V^.Data[1] / W);
        MaxVar(Result.Data[1].Data[2], V^.Data[2] / W);
      end;
    end;
  end else
  { Otherwise, all the Weights are assumed 1.0 }
    Result := CalculateBoundingBox(Point);
end;

function NurbsBoundingBox(Point: TVector3List;
  Weight: TSingleList): TBox3D;
var
  WeightDouble: TDoubleList;
begin
  { Direct implementation using single would be much faster...
    But not important, this is only for old VRML 2.0, not for X3D. }
  WeightDouble := Weight.ToDouble;
  try
    Result := NurbsBoundingBox(Point, WeightDouble);
  finally FreeAndNil(WeightDouble) end;
end;

function NurbsBoundingBox(Point: TVector3List;
  Weight: TDoubleList; const Transform: TMatrix4): TBox3D;
var
  V: TVector3;
  W: Single;
  I: Integer;
begin
  if Weight.Count = Point.Count then
  begin
    if Point.Count = 0 then
      Result := TBox3D.Empty else
    begin
      W := Weight.List^[0];
      if W = 0 then W := 1;

      Result.Data[0] := Transform.MultPoint(Point.List^[0] / W);
      Result.Data[1] := Result.Data[0];

      for I := 1 to Point.Count - 1 do
      begin
        W := Weight.List^[I];
        if W = 0 then W := 1;

        V := Transform.MultPoint(Point.List^[I] / W);

        MinVar(Result.Data[0].Data[0], V[0]);
        MinVar(Result.Data[0].Data[1], V[1]);
        MinVar(Result.Data[0].Data[2], V[2]);

        MaxVar(Result.Data[1].Data[0], V[0]);
        MaxVar(Result.Data[1].Data[1], V[1]);
        MaxVar(Result.Data[1].Data[2], V[2]);
      end;
    end;
  end else
  { Otherwise, all the Weights are assumed 1.0 }
    Result := CalculateBoundingBox(Point, Transform);
end;

function NurbsBoundingBox(Point: TVector3List;
  Weight: TSingleList; const Transform: TMatrix4): TBox3D;
var
  WeightDouble: TDoubleList;
begin
  { Direct implementation using single would be much faster...
    But not important, this is only for old VRML 2.0, not for X3D. }
  WeightDouble := Weight.ToDouble;
  try
    Result := NurbsBoundingBox(Point, WeightDouble, Transform);
  finally
    FreeAndNil(WeightDouble)
  end;
end;

end.
