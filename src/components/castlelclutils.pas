{
  Copyright 2008-2018 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Utilities for cooperation between LCL and "Castle Game Engine". }
unit CastleLCLUtils;

{$I castleconf.inc}

interface

uses Dialogs, Classes, Controls, CastleFileFilters, CastleKeysMouse,
  Graphics, CastleVectors;

{ Convert file filters into LCL Dialog.Filter, Dialog.FilterIndex.
  Suitable for both open and save dialogs (TOpenDialog, TSaveDialog
  both descend from TFileDialog).

  Input filters are either given as a string FileFilters
  (encoded just like for TFileFilterList.AddFiltersFromString),
  or as TFileFilterList instance.

  Output filters are either written to LCLFilter, LCLFilterIndex
  variables, or set appropriate properties of given Dialog instance.

  When AllFields is false, then filters starting with "All " in the name,
  like "All files", "All images", are not included in the output.

  @groupBegin }
procedure FileFiltersToDialog(const FileFilters: string;
  Dialog: TFileDialog; const AllFields: boolean = true);
procedure FileFiltersToDialog(const FileFilters: string;
  out LCLFilter: string; out LCLFilterIndex: Integer; const AllFields: boolean = true);
procedure FileFiltersToDialog(FFList: TFileFilterList;
  Dialog: TFileDialog; const AllFields: boolean = true);
procedure FileFiltersToDialog(FFList: TFileFilterList;
  out LCLFilter: string; out LCLFilterIndex: Integer; const AllFields: boolean = true);
{ @groupEnd }

{ Make each '&' inside string '&&', this way the string will not contain
  special '&x' sequences when used as a TMenuItem.Caption and such. }
function SQuoteLCLCaption(const S: string): string;

{ Deprecated names, use the identifiers without "Open" in new code.
  @deprecated
  @groupBegin }
procedure FileFiltersToOpenDialog(const FileFilters: string;
  Dialog: TFileDialog); deprecated;
procedure FileFiltersToOpenDialog(const FileFilters: string;
  out LCLFilter: string; out LCLFilterIndex: Integer); deprecated;
procedure FileFiltersToOpenDialog(FFList: TFileFilterList;
  out LCLFilter: string; out LCLFilterIndex: Integer); deprecated;
{ @groupEnd }

{ Convert Key (Lazarus key code) to Castle Game Engine TKey.

  In addition, this tries to convert Key to a character (MyCharKey).
  It's awful that this function has to do conversion to Char,
  but that's the way of VCL and LCL: KeyPress and KeyDown
  are separate events. While I want to have them in one event,
  and passed as one event to TUIControl.KeyDown. }
procedure KeyLCLToCastle(const Key: Word; const Shift: TShiftState;
  out MyKey: TKey; out MyCharKey: char);

{ Convert TKey and/or character code into Lazarus key code (VK_xxx)
  and shift state.
  Sets LazKey to VK_UNKNOWN (zero) when conversion not possible
  (or when Key is keyNone and CharKey = #0).

  Note that this is not a perfect reverse of KeyLCLToCastle function.
  It can't, as there are ambiguities (e.g. character 'A' may
  be a key keyA with mkShift in modifiers).

  @groupBegin }
procedure KeyCastleToLCL(const Key: TKey; const CharKey: char;
  const Modifiers: TModifierKeys;
  out LazKey: Word; out Shift: TShiftState);
procedure KeyCastleToLCL(const Key: TKey; const CharKey: char;
  out LazKey: Word; out Shift: TShiftState);
{ @groupEnd }

{ Convert Lazarus Controls.TMouseButton value to Castle Game Engine
  CastleKeysMouse.TMouseButton.

  (By coincidence, my type name and values are the same as used by LCL;
  but beware --- the order of values in my type is different (mbMiddle
  is in the middle in my type)). }
function MouseButtonLCLToCastle(
  const MouseButton: Controls.TMouseButton;
  out MyMouseButton: CastleKeysMouse.TMouseButton): boolean;

const
  CursorCastleToLCL: array [TMouseCursor] of TCursor =
  ( crDefault, crNone, crNone, crDefault { mcCustom treat like mcDefault },
    crArrow, crHourGlass, crIBeam, crHandPoint );

function FilenameToURISafeUTF8(const FileName: string): string;
function URIToFilenameSafeUTF8(const URL: string): string;

{ Convert LCL color values to our colors (vectors). }
function ColorToVector3(const Color: TColor): TVector3;
function ColorToVector3Byte(const Color: TColor): TVector3Byte;

implementation

uses SysUtils, FileUtil, LazUTF8, LCLType, LCLProc,
  CastleClassUtils, CastleStringUtils, CastleURIUtils, CastleLog;

procedure FileFiltersToDialog(const FileFilters: string;
  Dialog: TFileDialog; const AllFields: boolean);
var
  LCLFilter: string;
  LCLFilterIndex: Integer;
begin
  FileFiltersToDialog(FileFilters, LCLFilter, LCLFilterIndex, AllFields);
  Dialog.Filter := LCLFilter;
  Dialog.FilterIndex := LCLFilterIndex;
end;

procedure FileFiltersToDialog(const FileFilters: string;
  out LCLFilter: string; out LCLFilterIndex: Integer; const AllFields: boolean);
var
  FFList: TFileFilterList;
begin
  FFList := TFileFilterList.Create(true);
  try
    FFList.AddFiltersFromString(FileFilters);
    FileFiltersToDialog(FFList, LCLFilter, LCLFilterIndex, AllFields);
  finally FreeAndNil(FFList) end;
end;

procedure FileFiltersToDialog(FFList: TFileFilterList;
  Dialog: TFileDialog; const AllFields: boolean);
var
  LCLFilter: string;
  LCLFilterIndex: Integer;
begin
  FileFiltersToDialog(FFList, LCLFilter, LCLFilterIndex, AllFields);
  Dialog.Filter := LCLFilter;
  Dialog.FilterIndex := LCLFilterIndex;
end;

procedure FileFiltersToDialog(FFList: TFileFilterList;
  out LCLFilter: string; out LCLFilterIndex: Integer; const AllFields: boolean);
var
  Filter: TFileFilter;
  I, J: Integer;
begin
  LCLFilter := '';

  { initialize LCLFilterIndex.
    Will be corrected for AllFields=false case, and will be incremented
    (because LCL FilterIndex counts from 1) later. }

  LCLFilterIndex := FFList.DefaultFilter;

  for I := 0 to FFList.Count - 1 do
  begin
    Filter := FFList[I];
    if (not AllFields) and IsPrefix('All ', Filter.Name) then
    begin
      { then we don't want to add this to LCLFilter.
        We also need to fix LCLFilterIndex, to shift it. }
      if I = FFList.DefaultFilter then
        LCLFilterIndex := 0 else
      if I < FFList.DefaultFilter then
        Dec(LCLFilterIndex);
      Continue;
    end;

    LCLFilter += Filter.Name + '|';

    for J := 0 to Filter.Patterns.Count - 1 do
    begin
      if J <> 0 then LCLFilter += ';';
      LCLFilter += Filter.Patterns[J];
    end;

    LCLFilter += '|';
  end;

  { LCL FilterIndex counts from 1. }
  Inc(LCLFilterIndex);
end;

function SQuoteLCLCaption(const S: string): string;
begin
  Result := StringReplace(S, '&', '&&', [rfReplaceAll]);
end;

{ FileFiltersToOpenDialog are deprecated, just call versions without "Open". }
procedure FileFiltersToOpenDialog(const FileFilters: string;
  Dialog: TFileDialog);
begin
  FileFiltersToDialog(FileFilters, Dialog);
end;

procedure FileFiltersToOpenDialog(const FileFilters: string;
  out LCLFilter: string; out LCLFilterIndex: Integer);
begin
  FileFiltersToDialog(FileFilters, LCLFilter, LCLFilterIndex);
end;

procedure FileFiltersToOpenDialog(FFList: TFileFilterList;
  out LCLFilter: string; out LCLFilterIndex: Integer);
begin
  FileFiltersToDialog(FFList, LCLFilter, LCLFilterIndex);
end;

const
  { Ctrl key on most systems, Command key on macOS. }
  ssCtrlOrCommand = {$ifdef DARWIN} ssMeta {$else} ssCtrl {$endif};

procedure KeyLCLToCastle(const Key: Word; const Shift: TShiftState;
  out MyKey: TKey; out MyCharKey: char);
begin
  MyKey := keyNone;
  MyCharKey := #0;

  case Key of
    VK_BACK:       begin MyKey := keyBackSpace;       MyCharKey := CharBackSpace; end;
    VK_TAB:        begin MyKey := keyTab;             MyCharKey := CharTab;       end;
    VK_RETURN:     begin MyKey := keyEnter;           MyCharKey := CharEnter;     end;
    VK_SHIFT:            MyKey := keyShift;
    VK_CONTROL:          MyKey := keyCtrl;
    VK_MENU:             MyKey := keyAlt;
    VK_ESCAPE:     begin MyKey := keyEscape;          MyCharKey := CharEscape;    end;
    VK_SPACE:      begin MyKey := keySpace;           MyCharKey := ' ';           end;
    VK_PRIOR:            MyKey := keyPageUp;
    VK_NEXT:             MyKey := keyPageDown;
    VK_END:              MyKey := keyEnd;
    VK_HOME:             MyKey := keyHome;
    VK_LEFT:             MyKey := keyLeft;
    VK_UP:               MyKey := keyUp;
    VK_RIGHT:            MyKey := keyRight;
    VK_DOWN:             MyKey := keyDown;
    VK_INSERT:           MyKey := keyInsert;
    VK_DELETE:     begin MyKey := keyDelete;          MyCharKey := CharDelete; end;
    VK_ADD:        begin MyKey := keyNumpad_Plus;     MyCharKey := '+';        end;
    VK_SUBTRACT:   begin MyKey := keyNumpad_Minus;    MyCharKey := '-';        end;
    VK_SNAPSHOT:         MyKey := keyPrintScreen;
    VK_NUMLOCK:          MyKey := keyNumLock;
    VK_SCROLL:           MyKey := keyScrollLock;
    VK_CAPITAL:          MyKey := keyCapsLock;
    VK_PAUSE:            MyKey := keyPause;
    VK_OEM_COMMA:  begin MyKey := keyComma;           MyCharKey := ','; end;
    VK_OEM_PERIOD: begin MyKey := keyPeriod;          MyCharKey := '.'; end;
    VK_NUMPAD0:    begin MyKey := keyNumpad_0;        MyCharKey := '0'; end;
    VK_NUMPAD1:    begin MyKey := keyNumpad_1;        MyCharKey := '1'; end;
    VK_NUMPAD2:    begin MyKey := keyNumpad_2;        MyCharKey := '2'; end;
    VK_NUMPAD3:    begin MyKey := keyNumpad_3;        MyCharKey := '3'; end;
    VK_NUMPAD4:    begin MyKey := keyNumpad_4;        MyCharKey := '4'; end;
    VK_NUMPAD5:    begin MyKey := keyNumpad_5;        MyCharKey := '5'; end;
    VK_NUMPAD6:    begin MyKey := keyNumpad_6;        MyCharKey := '6'; end;
    VK_NUMPAD7:    begin MyKey := keyNumpad_7;        MyCharKey := '7'; end;
    VK_NUMPAD8:    begin MyKey := keyNumpad_8;        MyCharKey := '8'; end;
    VK_NUMPAD9:    begin MyKey := keyNumpad_9;        MyCharKey := '9'; end;
    VK_CLEAR:            MyKey := keyNumpad_Begin;
    VK_MULTIPLY:   begin MyKey := keyNumpad_Multiply; MyCharKey := '*'; end;
    VK_DIVIDE:     begin MyKey := keyNumpad_Divide;   MyCharKey := '/'; end;
    VK_OEM_MINUS:  begin MyKey := keyMinus;           MyCharKey := '-'; end;
    VK_OEM_PLUS:
      if ssShift in Shift then
      begin
        MyKey := keyPlus ; MyCharKey := '+';
      end else
      begin
        MyKey := keyEqual; MyCharKey := '=';
      end;

    Ord('0') .. Ord('9'):
      begin
        MyKey := TKey(Ord(key0)  + Ord(Key) - Ord('0'));
        MyCharKey := Chr(Key);
      end;

    Ord('A') .. Ord('Z'):
      begin
        MyKey := TKey(Ord(keyA)  + Ord(Key) - Ord('A'));
        if ssCtrlOrCommand in Shift then
          MyCharKey := Chr(Ord(CtrlA) + Ord(Key) - Ord('A')) else
        begin
          MyCharKey := Chr(Key);
          if not (ssShift in Shift) then
            MyCharKey := LoCase(MyCharKey);
        end;
      end;

    VK_F1 .. VK_F12  : MyKey := TKey(Ord(keyF1) + Ord(Key) - VK_F1);
  end;

  if (MyKey = keyNone) and (MyCharKey = #0) then
    WritelnLog('LCL', 'Cannot translate LCL VK_xxx key %s with shift %s to Castle Game Engine key',
      [DbgsVKCode(Key), DbgS(Shift)]);
end;

procedure KeyCastleToLCL(const Key: TKey; const CharKey: char;
  out LazKey: Word; out Shift: TShiftState);
begin
  KeyCastleToLCL(Key, CharKey, [], LazKey, Shift);
end;

procedure KeyCastleToLCL(const Key: TKey; const CharKey: char;
  const Modifiers: TModifierKeys;
  out LazKey: Word; out Shift: TShiftState);
begin
  Shift := [];
  LazKey := VK_UNKNOWN;
  case Key of
    keyBackSpace:        LazKey := VK_BACK;
    keyTab:              LazKey := VK_TAB;
    keyEnter:            LazKey := VK_RETURN;
    keyShift:            LazKey := VK_SHIFT;
    keyCtrl:             LazKey := VK_CONTROL;
    keyAlt:              LazKey := VK_MENU;
    keyEscape:           LazKey := VK_ESCAPE;
    keySpace:            LazKey := VK_SPACE;
    keyPageUp:           LazKey := VK_PRIOR;
    keyPageDown:         LazKey := VK_NEXT;
    keyEnd:              LazKey := VK_END;
    keyHome:             LazKey := VK_HOME;
    keyLeft:             LazKey := VK_LEFT;
    keyUp:               LazKey := VK_UP;
    keyRight:            LazKey := VK_RIGHT;
    keyDown:             LazKey := VK_DOWN;
    keyInsert:           LazKey := VK_INSERT;
    keyDelete:           LazKey := VK_DELETE;
    keyNumpad_Plus:      LazKey := VK_ADD;
    keyNumpad_Minus:     LazKey := VK_SUBTRACT;
    keyPrintScreen:      LazKey := VK_SNAPSHOT;
    keyNumLock:          LazKey := VK_NUMLOCK;
    keyScrollLock:       LazKey := VK_SCROLL;
    keyCapsLock:         LazKey := VK_CAPITAL;
    keyPause:            LazKey := VK_PAUSE;
    keyComma:            LazKey := VK_OEM_COMMA;
    keyPeriod:           LazKey := VK_OEM_PERIOD;
    keyNumpad_0:         LazKey := VK_NUMPAD0;
    keyNumpad_1:         LazKey := VK_NUMPAD1;
    keyNumpad_2:         LazKey := VK_NUMPAD2;
    keyNumpad_3:         LazKey := VK_NUMPAD3;
    keyNumpad_4:         LazKey := VK_NUMPAD4;
    keyNumpad_5:         LazKey := VK_NUMPAD5;
    keyNumpad_6:         LazKey := VK_NUMPAD6;
    keyNumpad_7:         LazKey := VK_NUMPAD7;
    keyNumpad_8:         LazKey := VK_NUMPAD8;
    keyNumpad_9:         LazKey := VK_NUMPAD9;
    keyNumpad_Begin:     LazKey := VK_CLEAR;
    keyNumpad_Multiply:  LazKey := VK_MULTIPLY;
    keyNumpad_Divide:    LazKey := VK_DIVIDE;
    keyMinus:            LazKey := VK_OEM_MINUS;
    keyEqual:            LazKey := VK_OEM_PLUS;

    { TKey ranges }
    key0 ..key9  : LazKey := Ord('0') + Ord(Key) - Ord(key0);
    keyA ..keyZ  : LazKey := Ord('A') + Ord(Key) - Ord(keyA);
    keyF1..keyF12: LazKey :=    VK_F1 + Ord(Key) - Ord(keyF1);

    else
      case CharKey of
        { follow TMenuItem.Key docs: when Key is keyNone, only CharKey indicates
          CharBackSpace / CharTab / CharEnter, convert them to Ctrl+xxx shortcuts }
        //CharBackSpace:              LazKey := VK_BACK;
        //CharTab:                    LazKey := VK_TAB;
        //CharEnter:                  LazKey := VK_RETURN;
        CharEscape:                 LazKey := VK_ESCAPE;
        ' ':                        LazKey := VK_SPACE;
        CharDelete:                 LazKey := VK_DELETE;
        '+':                        LazKey := VK_ADD;
        '-':                        LazKey := VK_SUBTRACT;
        ',':                        LazKey := VK_OEM_COMMA;
        '.':                        LazKey := VK_OEM_PERIOD;
        '*':                        LazKey := VK_MULTIPLY;
        '/':                        LazKey := VK_DIVIDE;
        '=':                        LazKey := VK_OEM_PLUS;

        { Char ranges }
        '0' .. '9' : LazKey := Ord(CharKey);
        { for latter: uppercase letters are VK_xxx codes }
        'A' .. 'Z' : begin LazKey := Ord(CharKey); Shift := [ssShift]; end;
        'a' .. 'z' : begin LazKey := Ord(UpCase(CharKey)); end;
        CtrlA .. CtrlZ:
          begin
            LazKey := Ord('A') + Ord(CharKey) - Ord(CtrlA);
            Shift := [ssCtrlOrCommand];
          end;
      end;
  end;

  if mkShift in Modifiers then
    Shift += [ssShift];
  if mkCtrl in Modifiers then
    Shift += [ssCtrlOrCommand];
  if mkAlt in Modifiers then
    Shift += [ssAlt];
end;

function MouseButtonLCLToCastle(
  const MouseButton: Controls.TMouseButton;
  out MyMouseButton: CastleKeysMouse.TMouseButton): boolean;
begin
  Result := true;
  case MouseButton of
    Controls.mbLeft  : MyMouseButton := CastleKeysMouse.mbLeft;
    Controls.mbRight : MyMouseButton := CastleKeysMouse.mbRight;
    Controls.mbMiddle: MyMouseButton := CastleKeysMouse.mbMiddle;
    Controls.mbExtra1: MyMouseButton := CastleKeysMouse.mbExtra1;
    Controls.mbExtra2: MyMouseButton := CastleKeysMouse.mbExtra2;
    else Result := false;
  end;
end;

function FilenameToURISafeUTF8(const FileName: string): string;
begin
  Result := FilenameToURISafe(UTF8ToSys(FileName));
end;

function URIToFilenameSafeUTF8(const URL: string): string;
begin
  Result := SysToUTF8(URIToFilenameSafe(URL));
end;

function ColorToVector3(const Color: TColor): TVector3;
begin
  Result := Vector3(ColorToVector3Byte(Color));
end;

function ColorToVector3Byte(const Color: TColor): TVector3Byte;
var
  Col: LongInt;
begin
  Col := ColorToRGB(Color);
  RedGreenBlue(Col, Result.Data[0], Result.Data[1], Result.Data[2]);
end;

end.
