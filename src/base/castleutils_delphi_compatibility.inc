{
  Copyright 2017-2018 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Useful things from FPC RTL defined for Delphi. }

// This whole file is only used for Delphi, FPC already has this.
{$ifndef FPC}

{$ifdef read_interface}

const
  LineEnding = SLineBreak;

type
  SizeInt = Integer;

  QWord = UInt64;
  PQWord = PUInt64;

  PtrInt = NativeInt;
  PtrUInt = NativeUInt;

  TGetVendorNameEvent  = function: string;
  TGetAppNameEvent  = function: string;

var
  OnGetVendorName      : TGetVendorNameEvent;
  OnGetApplicationName : TGetAppNameEvent;

function GetMem(const Size: Integer): Pointer;
function VendorName: string;
function ApplicationName: string;
function GetAppConfigDir(Global : Boolean) : String;

function StringsReplace(const S: string; OldPattern, NewPattern: array of string;  Flags: TReplaceFlags): string;
{$endif read_interface}

{$ifdef read_implementation}

function GetMem(const Size: Integer): Pointer;
begin
  System.GetMem(Result, Size);
end;

{ Copied from FPC RTL (same license as Castle Game Engine) }
function VendorName : String;
begin
  If Assigned(OnGetVendorName) then
    Result:=OnGetVendorName()
  else
    Result:='';
end;

{ Copied from FPC RTL (same license as Castle Game Engine) }
function ApplicationName : String;
begin
  If Assigned(OnGetApplicationName) then
    Result:=OnGetApplicationName()
  else
    Result:=ChangeFileExt(ExtractFileName(Paramstr(0)),'');
end;

{ Copied from FPC RTL (same license as Castle Game Engine) and adjusted }
function GetWindowsSpecialDirUnicode(ID: Integer; CreateIfNotExists: Boolean = True): UnicodeString;
var
  Buffer: array [0..MAX_PATH] of WideChar;
begin
  Result := '';
  if SHGetSpecialFolderPathW(0, @Buffer[0], ID, CreateIfNotExists) then
    Result := IncludeTrailingPathDelimiter(StrPas(Buffer));
end;

{ Copied from FPC RTL (same license as Castle Game Engine) }
function GetWindowsSpecialDir(ID: Integer; CreateIfNotExists: Boolean = True): String;
begin
  Result := String(GetWindowsSpecialDirUnicode(ID, CreateIfNotExists));
end;

function DGetAppConfigDir(Global : Boolean) : String;
begin
  Result:=ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
end;

{ Copied from FPC RTL (same license as Castle Game Engine) }
function GetAppConfigDir(Global : Boolean) : String;
begin
  If Global then
    Result:=GetWindowsSpecialDir(CSIDL_COMMON_APPDATA)
  else
    Result:=GetWindowsSpecialDir(CSIDL_LOCAL_APPDATA);
  If (Result<>'') then
  begin
    if VendorName<>'' then
      Result:=IncludeTrailingPathDelimiter(Result+VendorName);
    Result:=IncludeTrailingPathDelimiter(Result+ApplicationName);
  end else
    Result:=IncludeTrailingPathDelimiter(DGetAppConfigDir(Global));
end;

function StringsReplace(const S: string; OldPattern, NewPattern: array of string;  Flags: TReplaceFlags): string;

var pc,pcc,lastpc : pchar;
    StrCount      : integer;
    ResStr,
    CompStr       : string;
    Found         : Boolean;
    sc            : sizeint;

begin
  sc := length(OldPattern);
  if sc <> length(NewPattern) then
    raise exception.Create('Amount of search and replace strings don''t match');

  Dec(sc);

  if rfIgnoreCase in Flags then
  begin
    CompStr:=AnsiUpperCase(S);
    for StrCount := 0 to sc do
      OldPattern[StrCount] := AnsiUpperCase(OldPattern[StrCount]);
  end else
    CompStr := s;

  ResStr := '';
  pc := @CompStr[1];
  pcc := @s[1];
  lastpc := pc + Length(S);

  while pc < lastpc do
  begin
    Found := False;
    for StrCount := 0 to sc do
    begin
      if (length(OldPattern[StrCount]) > 0) and
         (OldPattern[StrCount][1] = pc^) and
         (Length(OldPattern[StrCount]) <= (lastpc-pc)) and
         CompareMem(Pointer(OldPattern[StrCount]), pc, Length(OldPattern[StrCount])) then
      begin
        ResStr := ResStr + NewPattern[StrCount];
        pc := pc + Length(OldPattern[StrCount]);
        pcc := pcc + Length(OldPattern[StrCount]);
        Found := true;
      end
    end;
    if not found then
    begin
      ResStr := ResStr + pcc^;
      Inc(pc);
      Inc(pcc);
    end else
      if not (rfReplaceAll in Flags) then
      begin
        ResStr := ResStr + StrPas(pcc);
        Break;
      end;
  end;
  Result := ResStr;
end;

{$endif read_implementation}

{$endif not FPC}
