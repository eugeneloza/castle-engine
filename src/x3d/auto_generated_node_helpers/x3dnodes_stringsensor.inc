{ -*- buffer-read-only: t -*-

  Copyright 2015-2018 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automatically generated node properties.

  Do not edit this file manually!
  To add new properties:
  - add them to the text files in nodes_specification/components/ ,
  - and regenerate include files by running
    nodes_specification/x3d-nodes-to-pascal/x3d-nodes-to-pascal.lpr .

  The documentation for properties should go to x3dnodes_documentation.txt . }

{$ifdef read_interface}

  strict private
    function GetDeletionAllowed: boolean;
    procedure SetDeletionAllowed(const Value: boolean);
  public
    { X3D field "deletionAllowed". } { }
    property DeletionAllowed: boolean read GetDeletionAllowed write SetDeletionAllowed;

{$endif read_interface}

{$ifdef read_implementation}

{ TStringSensorNode ----------------------------------------------- }

function TStringSensorNode.GetDeletionAllowed: boolean;
begin
  Result := FdDeletionAllowed.Value;
end;

procedure TStringSensorNode.SetDeletionAllowed(const Value: boolean);
begin
  FdDeletionAllowed.Send(Value);
end;

{$endif read_implementation}
