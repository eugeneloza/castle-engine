{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2013 by Yury Sidorov,
    member of the Free Pascal development team.

    Wide string support for Android

    This file is adapted from the FPC RTL source code, as such
    the license and copyright information of FPC RTL applies here.
    That said, the license of FPC RTL happens to be *exactly*
    the same as used by the "Castle Game Engine": LGPL (version 2.1)
    with "static linking exception" (with exactly the same wording
    of the "static linking exception").
    See the file COPYING.txt, included in this distribution, for details about
    the copyright of "Castle Game Engine".
    See http://www.freepascal.org/faq.var#general-license about the copyright
    of FPC RTL.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 **********************************************************************}

{$I castleconf.inc}
{$inline on}
{$implicitexceptions off}

{ Reworked FPC CWString, to delay loading of library until Android
  activity started, necessary on some Android versions.
  @exclude Not documented for PasDoc. }
unit CastleAndroidInternalCWString;

{ This should be defined only in FPC >= 3.0.2. }
{$define FPC_NEW_VERSION_WITH_UNICODE}
{$ifdef VER3_0_0}
  {$undef FPC_NEW_VERSION_WITH_UNICODE}
{$endif}
{$ifdef VER2_6}
  {$undef FPC_NEW_VERSION_WITH_UNICODE}
{$endif}

interface

procedure SetCWidestringManager;

{ Call this once Android activity started to initialize CWString. }
procedure InitializeAndroidCWString;

implementation

uses dynlibs, CastleAndroidInternalLog;

type
  UErrorCode = SizeInt;
  int32_t = longint;
  uint32_t = longword;
  PUConverter = pointer;
  PUCollator = pointer;
  UBool = LongBool;

var
  hlibICU: TLibHandle;
  hlibICUi18n: TLibHandle;
  ucnv_open: function (converterName: PAnsiChar; var pErrorCode: UErrorCode): PUConverter; cdecl;
  ucnv_close: procedure (converter: PUConverter); cdecl;
  ucnv_setSubstChars: procedure (converter: PUConverter; subChars: PAnsiChar; len: byte; var pErrorCode: UErrorCode); cdecl;
  ucnv_setFallback: procedure (cnv: PUConverter; usesFallback: UBool); cdecl;
  ucnv_fromUChars: function (cnv: PUConverter; dest: PAnsiChar; destCapacity: int32_t; src: PUnicodeChar; srcLength: int32_t; var pErrorCode: UErrorCode): int32_t; cdecl;
  ucnv_toUChars: function (cnv: PUConverter; dest: PUnicodeChar; destCapacity: int32_t; src: PAnsiChar; srcLength: int32_t; var pErrorCode: UErrorCode): int32_t; cdecl;
  u_strToUpper: function (dest: PUnicodeChar; destCapacity: int32_t; src: PUnicodeChar; srcLength: int32_t; locale: PAnsiChar; var pErrorCode: UErrorCode): int32_t; cdecl;
  u_strToLower: function (dest: PUnicodeChar; destCapacity: int32_t; src: PUnicodeChar; srcLength: int32_t; locale: PAnsiChar; var pErrorCode: UErrorCode): int32_t; cdecl;
  u_strCompare: function (s1: PUnicodeChar; length1: int32_t; s2: PUnicodeChar; length2: int32_t; codePointOrder: UBool): int32_t; cdecl;
  u_strCaseCompare: function (s1: PUnicodeChar; length1: int32_t; s2: PUnicodeChar; length2: int32_t; options: uint32_t; var pErrorCode: UErrorCode): int32_t; cdecl;

  ucol_open: function(loc: PAnsiChar; var status: UErrorCode): PUCollator; cdecl;
  ucol_close: procedure (coll: PUCollator); cdecl;
  ucol_strcoll: function (coll: PUCollator; source: PUnicodeChar; sourceLength: int32_t; target: PUnicodeChar; targetLength: int32_t): int32_t; cdecl;
	ucol_setStrength: procedure (coll: PUCollator; strength: int32_t); cdecl;
  u_errorName: function (code: UErrorCode): PAnsiChar; cdecl;

threadvar
  ThreadDataInited: boolean;
  DefConv, LastConv: PUConverter;
  LastCP: TSystemCodePage;
  DefColl: PUCollator;

function OpenConverter(const Name: ansistring): PUConverter;
var
  Err: UErrorCode;
begin
  Err := 0;
  Result := ucnv_open(PAnsiChar(Name), Err);
  if Result <> nil then
  begin
    ucnv_setSubstChars(Result, '?', 1, Err);
    ucnv_setFallback(Result, True);
  end;
end;

procedure InitThreadData;
var
  Err: UErrorCode;
  Col: PUCollator;
begin
  if (hlibICU = 0) or ThreadDataInited then
    Exit;
  ThreadDataInited := True;
  DefConv := OpenConverter('utf8');
  Err := 0;
  Col := ucol_open(nil, Err);
  if Col <> nil then
    ucol_setStrength(Col, 2);
  DefColl := Col;
end;

{$ifdef FPC_NEW_VERSION_WITH_UNICODE}

function GetConverter(cp: TSystemCodePage): PUConverter;
var
  S: ansistring;
begin
  if hlibICU = 0 then begin
    Result := nil;
    Exit;
  end;
  InitThreadData;
  if (cp = CP_UTF8) or (cp = CP_ACP) then
    Result := DefConv
  else
  begin
    if cp <> LastCP then begin
      Str(cp, S);
      LastConv := OpenConverter('cp' + S);
      LastCP := cp;
    end;
    Result := LastConv;
  end;
end;

procedure Unicode2AnsiMove(Source: PUnicodeChar; var Dest: RawByteString; cp: TSystemCodePage; Len: SizeInt);
var
  Len2: SizeInt;
  Conv: PUConverter;
  Err: UErrorCode;
begin
  if Len = 0 then
  begin
    Dest := '';
    Exit;
  end;
  Conv := GetConverter(cp);
  if (Conv = nil) and not ( (cp = CP_UTF8) or (cp = CP_ACP) ) then
  begin
    // fallback implementation
    DefaultUnicode2AnsiMove(Source, Dest, DefaultSystemCodePage, Len);
    Exit;
  end;

  Len2 := Len * 3;
  SetLength(Dest, Len2);
  Err := 0;
  if Conv <> nil then
    Len2 := ucnv_fromUChars(Conv, PAnsiChar(Dest), Len2, Source, Len, Err)
  else
  begin
    // Use UTF-8 conversion from RTL
    cp := CP_UTF8;
    Len2 := UnicodeToUtf8(PAnsiChar(Dest), Len2, Source, Len) - 1;
  end;
  if Len2 > Length(Dest) then
  begin
    SetLength(Dest, Len2);
    Err := 0;
    if conv <> nil then
      Len2 := ucnv_fromUChars(Conv, PAnsiChar(Dest), Len2, Source, Len, Err)
    else
      Len2 := UnicodeToUtf8(PAnsiChar(Dest), Len2, Source, Len) - 1;
  end;
  if Len2 < 0 then
    Len2 := 0;
  SetLength(Dest, Len2);
  SetCodePage(Dest, cp, false);
end;

procedure Ansi2UnicodeMove(Source: PChar; cp: TSystemCodePage; var Dest: unicodestring; Len:SizeInt);
var
  Len2: SizeInt;
  Conv: PUConverter;
  Err: UErrorCode;
begin
  if Len = 0 then
  begin
    Dest := '';
    Exit;
  end;
  Conv := GetConverter(cp);
  if (Conv = nil) and not ( (cp = CP_UTF8) or (cp = CP_ACP) ) then
  begin
    // fallback implementation
    DefaultAnsi2UnicodeMove(Source, DefaultSystemCodePage, Dest, Len);
    Exit;
  end;

  Len2 := Len;
  SetLength(Dest, Len2);
  Err := 0;
  if Conv <> nil then
    Len2 := ucnv_toUChars(Conv, PUnicodeChar(Dest), Len2, Source, Len, Err)
  else
    // Use UTF-8 conversion from RTL
    Len2 := Utf8ToUnicode(PUnicodeChar(Dest), Len2, Source, Len) - 1;
  if Len2 > Length(Dest) then
  begin
    SetLength(Dest, Len2);
    Err := 0;
    if Conv <> nil then
      Len2 := ucnv_toUChars(Conv, PUnicodeChar(Dest), Len2, Source, Len, Err)
    else
      Len2 := Utf8ToUnicode(PUnicodeChar(Dest), Len2, Source, Len) - 1;
  end;
  if Len2 < 0 then
    Len2 := 0;
  SetLength(Dest, Len2);
end;

function UpperUnicodeString(const S: UnicodeString): UnicodeString;
var
  Len, Len2: SizeInt;
  Err: UErrorCode;
begin
  if hlibICU = 0 then
  begin
    // fallback implementation
    Result := UnicodeString(UpCase(AnsiString(S)));
    Exit;
  end;
  Len := Length(S);
  SetLength(Result, Len);
  if Len = 0 then
    Exit;
  Err := 0;
  Len2 := u_strToUpper(PUnicodeChar(Result), Len, PUnicodeChar(S), Len, nil, Err);
  if Len2 > Len then begin
    SetLength(Result, Len2);
    Err := 0;
    Len2 := u_strToUpper(PUnicodeChar(Result), Len2, PUnicodeChar(S), Len, nil, Err);
  end;
  SetLength(Result, Len2);
end;

function LowerUnicodeString(const S: UnicodeString): UnicodeString;
var
  Len, Len2: SizeInt;
  Err: UErrorCode;
begin
  if hlibICU = 0 then
  begin
    // fallback implementation
    Result := UnicodeString(LowerCase(AnsiString(S)));
    Exit;
  end;
  Len := Length(S);
  SetLength(Result, Len);
  if Len = 0 then
    Exit;
  Err := 0;
  Len2 := u_strToLower(PUnicodeChar(Result), Len, PUnicodeChar(S), Len, nil, Err);
  if Len2 > Len then begin
    SetLength(Result, Len2);
    Err := 0;
    Len2 := u_strToLower(PUnicodeChar(Result), Len2, PUnicodeChar(S), Len, nil, Err);
  end;
  SetLength(Result, Len2);
end;

function _CompareStr(const S1, S2: UnicodeString): PtrInt;
var
  Count, Count1, Count2: SizeInt;
begin
  Result := 0;
  Count1 := Length(S1);
  Count2 := Length(S2);
  if Count1 > Count2 then
    Count := Count2
  else
    Count := Count1;
  Result := CompareByte(PUnicodeChar(S1)^, PUnicodeChar(S2)^, Count * SizeOf(UnicodeChar));
  if Result = 0 then
    Result := Count1 - Count2;
end;

function CompareUnicodeString(const S1, S2: UnicodeString; Options: TCompareOptions): PtrInt;
const
  U_COMPARE_CODE_POINT_ORDER = $8000;
var
  Err: UErrorCode;
begin
  if hlibICU = 0 then
  begin
    // fallback implementation
    Result := _CompareStr(S1, S2);
    Exit;
  end;
  if (coIgnoreCase in Options) then
  begin
    Err := 0;
    Result := u_strCaseCompare(PUnicodeChar(S1), Length(S1), PUnicodeChar(S2), Length(S2), U_COMPARE_CODE_POINT_ORDER, Err);
  end else
  begin
    InitThreadData;
    if DefColl <> nil then
      Result := ucol_strcoll(DefColl, PUnicodeChar(S1), Length(S1), PUnicodeChar(S2), Length(S2))
    else
      Result := u_strCompare(PUnicodeChar(S1), Length(S1), PUnicodeChar(S2), Length(S2), true);
  end;
end;

function UpperAnsiString(const S: AnsiString): AnsiString;
begin
  Result := AnsiString(UpperUnicodeString(UnicodeString(S)));
end;

function LowerAnsiString(const S: AnsiString): AnsiString;
begin
  Result := AnsiString(LowerUnicodeString(UnicodeString(S)));
end;

function CompareStrAnsiString(const S1, S2: ansistring): PtrInt;
begin
  Result := CompareUnicodeString(UnicodeString(S1), UnicodeString(S2), []);
end;

function StrCompAnsi(S1, S2: PChar): PtrInt;
begin
  Result := CompareUnicodeString(UnicodeString(S1), UnicodeString(S2), []);
end;

function AnsiCompareText(const S1, S2: ansistring): PtrInt;
begin
  Result := CompareUnicodeString(UnicodeString(S1), UnicodeString(S2), [coIgnoreCase]);
end;

function AnsiStrIComp(S1, S2: PChar): PtrInt;
begin
  Result := CompareUnicodeString(UnicodeString(S1), UnicodeString(S2), [coIgnoreCase]);
end;

function AnsiStrLComp(S1, S2: PChar; MaxLen: PtrUInt): PtrInt;
var
  AS1, AS2: ansistring;
begin
  SetString(AS1, S1, MaxLen);
  SetString(AS2, S2, MaxLen);
  Result := CompareUnicodeString(UnicodeString(AS1), UnicodeString(AS2), []);
end;

function AnsiStrLIComp(S1, S2: PChar; MaxLen: PtrUInt): PtrInt;
var
  AS1, AS2: ansistring;
begin
  SetString(AS1, S1, MaxLen);
  SetString(AS2, S2, MaxLen);
  Result := CompareUnicodeString(UnicodeString(AS1), UnicodeString(AS2), [coIgnoreCase]);
end;

function AnsiStrLower(Str: PChar): PChar;
var
  S, Res: ansistring;
begin
  S := Str;
  Res := LowerAnsiString(S);
  if Length(Res) > Length(S) then
    SetLength(Res, Length(S));
  Move(PAnsiChar(Res)^, Str, Length(Res) + 1);
  Result := Str;
end;

function AnsiStrUpper(Str: PChar): PChar;
var
  S, Res: ansistring;
begin
  S := Str;
  Res := UpperAnsiString(S);
  if Length(Res) > Length(S) then
    SetLength(Res, Length(S));
  Move(PAnsiChar(Res)^, Str, Length(Res) + 1);
  Result := Str;
end;

function CodePointLength(const Str: PChar; MaxLookAead: PtrInt): Ptrint;
var
  C: byte;
begin
  // Only UTF-8 encoding is supported
  C := byte(Str^);
  if C =  0 then
    Result:=0
  else
  begin
    Result := 1;
    if C < $80 then
      Exit; // 1-byte ASCII char
    while C and $C0 = $C0 do
    begin
      Inc(Result);
      C := C shl 1;
    end;
    if Result > 6 then
      Result := 1 // Invalid code point
    else
      if Result > MaxLookAead then
        Result := -1; // Incomplete code point
  end;
end;

function GetStandardCodePage(const stdcp: TStandardCodePageEnum): TSystemCodePage;
begin
  Result := CP_UTF8; // Android always uses UTF-8
end;

procedure SetStdIOCodePage(var T: Text); inline;
begin
  case TextRec(T).Mode of
    fmInput: TextRec(T).CodePage := DefaultSystemCodePage;
    fmOutput: TextRec(T).CodePage := DefaultSystemCodePage;
  end;
end;

procedure SetStdIOCodePages; inline;
begin
  SetStdIOCodePage(Input);
  SetStdIOCodePage(Output);
  SetStdIOCodePage(ErrOutput);
  SetStdIOCodePage(StdOut);
  SetStdIOCodePage(StdErr);
end;

procedure Ansi2WideMove(Source: PChar; cp: TSystemCodePage; var Dest: widestring; Len: SizeInt);
var
  US: UnicodeString;
begin
  Ansi2UnicodeMove(Source, cp, US, Len);
  Dest := US;
end;

function UpperWideString(const S: WideString): WideString;
begin
  Result := UpperUnicodeString(S);
end;

function LowerWideString(const S: WideString): WideString;
begin
  Result := LowerUnicodeString(S);
end;

function CompareWideString(const S1, S2: WideString; Options: TCompareOptions): PtrInt;
begin
  Result := CompareUnicodeString(S1, S2, Options);
end;

Procedure SetCWideStringManager;
Var
  CWideStringManager: TUnicodeStringManager;
begin
  CWideStringManager := widestringmanager;
  With CWideStringManager do
  begin
    Wide2AnsiMoveProc := @Unicode2AnsiMove;
    Ansi2WideMoveProc := @Ansi2WideMove;
    UpperWideStringProc := @UpperWideString;
    LowerWideStringProc := @LowerWideString;
    CompareWideStringProc := @CompareWideString;

    UpperAnsiStringProc := @UpperAnsiString;
    LowerAnsiStringProc := @LowerAnsiString;
    CompareStrAnsiStringProc := @CompareStrAnsiString;
    CompareTextAnsiStringProc := @AnsiCompareText;
    StrCompAnsiStringProc := @StrCompAnsi;
    StrICompAnsiStringProc := @AnsiStrIComp;
    StrLCompAnsiStringProc := @AnsiStrLComp;
    StrLICompAnsiStringProc := @AnsiStrLIComp;
    StrLowerAnsiStringProc := @AnsiStrLower;
    StrUpperAnsiStringProc := @AnsiStrUpper;

    Unicode2AnsiMoveProc := @Unicode2AnsiMove;
    Ansi2UnicodeMoveProc := @Ansi2UnicodeMove;
    UpperUnicodeStringProc := @UpperUnicodeString;
    LowerUnicodeStringProc := @LowerUnicodeString;
    CompareUnicodeStringProc := @CompareUnicodeString;

    GetStandardCodePageProc := @GetStandardCodePage;
    CodePointLengthProc := @CodePointLength;
  end;
  SetUnicodeStringManager(CWideStringManager);
end;

{$else}

function GetConverter(cp: TSystemCodePage): PUConverter;
var
  S: ansistring;
begin
  if hlibICU = 0 then
  begin
    Result := nil;
    Exit;
  end;
  InitThreadData;
  if (cp = DefaultSystemCodePage) or (cp = CP_ACP) then
    Result := DefConv
  else
  begin
    if cp <> LastCP then begin
      Str(cp, S);
      LastConv := OpenConverter('cp' + S);
      LastCP := cp;
    end;
    Result:=LastConv;
  end;
end;

procedure Unicode2AnsiMove(Source: PUnicodeChar; var Dest: RawByteString; cp: TSystemCodePage; Len: SizeInt);
var
  Len2: SizeInt;
  Conv: PUConverter;
  Err: UErrorCode;
begin
  if Len = 0 then
  begin
    Dest := '';
    Exit;
  end;
  Conv := GetConverter(cp);
  if Conv = nil then begin
    DefaultUnicode2AnsiMove(Source, Dest, DefaultSystemCodePage, Len);
    Exit;
  end;

  Len2 := Len * 3;
  SetLength(Dest, Len2);
  Err := 0;
  Len2 := ucnv_fromUChars(Conv, PAnsiChar(Dest), Len2, Source, Len, Err);
  if Len2 > Length(Dest) then
  begin
    SetLength(Dest, Len2);
    Err := 0;
    Len2 := ucnv_fromUChars(Conv, PAnsiChar(Dest), Len2, Source, Len, Err);
  end;
  SetLength(Dest, Len2);
  SetCodePage(Dest, cp, false);
end;

procedure Ansi2UnicodeMove(Source: PChar; cp: TSystemCodePage; var Dest: unicodestring; Len: SizeInt);
var
  Len2: SizeInt;
  Conv: PUConverter;
  Err: UErrorCode;
begin
  if Len = 0 then
  begin
    Dest := '';
    Exit;
  end;
  Conv := GetConverter(cp);
  if Conv = nil then
  begin
    DefaultAnsi2UnicodeMove(Source, DefaultSystemCodePage, Dest, Len);
    Exit;
  end;

  Len2 := len;
  SetLength(Dest, Len2);
  Err := 0;
  Len2 := ucnv_toUChars(Conv, PUnicodeChar(Dest), Len2, Source, Len, Err);
  if Len2 > Length(Dest) then
  begin
    SetLength(Dest, Len2);
    err := 0;
    Len2 := ucnv_toUChars(Conv, PUnicodeChar(Dest), Len2, Source, Len, Err);
  end;
  SetLength(Dest, Len2);
end;

function UpperUnicodeString(const S: UnicodeString): UnicodeString;
var
  Len, Len2: SizeInt;
  Err: UErrorCode;
begin
  if hlibICU = 0 then
  begin
    // fallback implementation
    Result := UnicodeString(UpCase(AnsiString(S)));
    Exit;
  end;
  Len := Length(S);
  SetLength(Result, Len);
  if Len = 0 then
    Exit;
  Err := 0;
  Len2 := u_strToUpper(PUnicodeChar(Result), Len, PUnicodeChar(S), Len, nil, Err);
  if Len2 > Len then begin
    SetLength(Result, Len2);
    Err := 0;
    Len2 := u_strToUpper(PUnicodeChar(Result), Len2, PUnicodeChar(S), Len, nil, Err);
  end;
  SetLength(Result, Len2);
end;

function LowerUnicodeString(const S: UnicodeString): UnicodeString;
var
  Len, Len2: SizeInt;
  Err: UErrorCode;
begin
  if hlibICU = 0 then
  begin
    // fallback implementation
    Result := UnicodeString(LowerCase(AnsiString(S)));
    Exit;
  end;
  Len := Length(S);
  SetLength(Result, Len);
  if Len = 0 then
    Exit;
  Err := 0;
  Len2 := u_strToLower(PUnicodeChar(Result), Len, PUnicodeChar(S), Len, nil, Err);
  if Len2 > Len then
  begin
    SetLength(Result, Len2);
    Err := 0;
    Len2 := u_strToLower(PUnicodeChar(Result), Len2, PUnicodeChar(S), Len, nil, Err);
  end;
  SetLength(Result, Len2);
end;

function _CompareStr(const S1, S2: UnicodeString): PtrInt;
var
  Count, Count1, Count2: SizeInt;
begin
  Result := 0;
  Count1 := Length(S1);
  Count2 := Length(S2);
  if Count1 > Count2 then
    Count := Count2
  else
    Count := Count1;
  Result := CompareByte(PUnicodeChar(S1)^, PUnicodeChar(S2)^, Count * SizeOf(UnicodeChar));
  if Result = 0 then
    Result := Count1 - Count2;
end;

function CompareUnicodeString(const S1, S2: UnicodeString): PtrInt;
begin
  if hlibICU = 0 then
  begin
    // fallback implementation
    Result := _CompareStr(S1, S2);
    Exit;
  end;
  InitThreadData;
  if DefColl <> nil then
    Result := ucol_strcoll(DefColl, PUnicodeChar(S1), Length(S1), PUnicodeChar(S2), Length(S2))
  else
    Result := u_strCompare(PUnicodeChar(S1), Length(S1), PUnicodeChar(S2), Length(S2), true);
end;

function CompareTextUnicodeString(const S1, S2: UnicodeString): PtrInt;
const
  U_COMPARE_CODE_POINT_ORDER = $8000;
var
  Err: UErrorCode;
begin
  if hlibICU = 0 then
  begin
    // fallback implementation
    Result := _CompareStr(UpperUnicodeString(S1), UpperUnicodeString(S2));
    Exit;
  end;
  Err := 0;
  Result := u_strCaseCompare(PUnicodeChar(S1), Length(S1), PUnicodeChar(S2), Length(S2), U_COMPARE_CODE_POINT_ORDER, Err);
end;

function UpperAnsiString(const S: AnsiString): AnsiString;
begin
  Result := AnsiString(UpperUnicodeString(UnicodeString(S)));
end;

function LowerAnsiString(const S: AnsiString): AnsiString;
begin
  Result := AnsiString(LowerUnicodeString(UnicodeString(S)));
end;

function CompareStrAnsiString(const S1, S2: ansistring): PtrInt;
begin
  Result := CompareUnicodeString(UnicodeString(S1), UnicodeString(S2));
end;

function StrCompAnsi(S1, S2: PChar): PtrInt;
begin
  Result := CompareUnicodeString(UnicodeString(S1), UnicodeString(S2));
end;

function AnsiCompareText(const S1, S2: ansistring): PtrInt;
begin
  Result := CompareTextUnicodeString(UnicodeString(S1), UnicodeString(S2));
end;

function AnsiStrIComp(S1, S2: PChar): PtrInt;
begin
  Result := CompareTextUnicodeString(UnicodeString(S1), UnicodeString(S2));
end;

function AnsiStrLComp(S1, S2: PChar; MaxLen: PtrUInt): PtrInt;
var
  AS1, AS2: ansistring;
begin
  SetString(AS1, S1, MaxLen);
  SetString(AS2, S2, MaxLen);
  Result := CompareUnicodeString(UnicodeString(AS2), UnicodeString(AS2));
end;

function AnsiStrLIComp(S1, S2: PChar; MaxLen: PtrUInt): PtrInt;
var
  AS1, AS2: ansistring;
begin
  SetString(AS1, S1, MaxLen);
  SetString(AS2, S2, MaxLen);
  Result := CompareTextUnicodeString(UnicodeString(AS1), UnicodeString(AS2));
end;

function AnsiStrLower(Str: PChar): PChar;
var
  S, Res: ansistring;
begin
  S := Str;
  Res := LowerAnsiString(S);
  if Length(Res) > Length(S) then
    SetLength(Res, Length(S));
  Move(PAnsiChar(Res)^, Str, Length(Res) + 1);
  Result := Str;
end;

function AnsiStrUpper(Str: PChar): PChar;
var
  S, Res: ansistring;
begin
  S := Str;
  Res := UpperAnsiString(S);
  if Length(Res) > Length(S) then
    SetLength(Res, Length(S));
  Move(PAnsiChar(Res)^, Str, Length(Res) + 1);
  Result := Str;
end;

function CodePointLength(const Str: PChar; MaxLookAead: PtrInt): Ptrint;
var
  C: byte;
begin
  // Only UTF-8 encoding is supported
  C := byte(Str^);
  if C = 0 then
    Result := 0
  else
  begin
    Result := 1;
    if C < $80 then
      Exit; // 1-byte ASCII char
    while C and $C0 = $C0 do begin
      Inc(Result);
      C := C shl 1;
    end;
    if Result > 6 then
      Result := 1 // Invalid code point
    else
      if Result > MaxLookAead then
        Result := -1; // Incomplete code point
  end;
end;

function GetStandardCodePage(const stdcp: TStandardCodePageEnum): TSystemCodePage;
begin
  Result := CP_UTF8; // Android always uses UTF-8
end;

procedure SetStdIOCodePage(var T: Text); {$ifdef SUPPORTS_INLINE} inline; {$endif}
begin
  case TextRec(T).Mode of
    fmInput: TextRec(T).CodePage := DefaultSystemCodePage;
    fmOutput: TextRec(T).CodePage := DefaultSystemCodePage;
  end;
end;

procedure SetStdIOCodePages; {$ifdef SUPPORTS_INLINE} inline; {$endif}
begin
  SetStdIOCodePage(Input);
  SetStdIOCodePage(Output);
  SetStdIOCodePage(ErrOutput);
  SetStdIOCodePage(StdOut);
  SetStdIOCodePage(StdErr);
end;

procedure Ansi2WideMove(Source: PChar; cp: TSystemCodePage; var Dest: widestring; Len: SizeInt);
var
  US: UnicodeString;
begin
  Ansi2UnicodeMove(Source, cp, US, Len);
  Dest := US;
end;

function UpperWideString(const S: WideString): WideString;
begin
  Result := UpperUnicodeString(S);
end;

function LowerWideString(const S: WideString): WideString;
begin
  Result := LowerUnicodeString(S);
end;

function CompareWideString(const S1, S2: WideString): PtrInt;
begin
  Result := CompareUnicodeString(S1, S2);
end;

function CompareTextWideString(const S1, S2: WideString): PtrInt;
begin
  Result := CompareTextUnicodeString(S1, S2);
end;

Procedure SetCWideStringManager;
Var
  CWideStringManager: TUnicodeStringManager;
begin
  CWideStringManager := widestringmanager;
  With CWideStringManager do
  begin
    Wide2AnsiMoveProc := @Unicode2AnsiMove;
    Ansi2WideMoveProc := @Ansi2WideMove;
    UpperWideStringProc := @UpperWideString;
    LowerWideStringProc := @LowerWideString;
    CompareWideStringProc := @CompareWideString;
    CompareTextWideStringProc := @CompareTextWideString;

    UpperAnsiStringProc := @UpperAnsiString;
    LowerAnsiStringProc := @LowerAnsiString;
    CompareStrAnsiStringProc := @CompareStrAnsiString;
    CompareTextAnsiStringProc := @AnsiCompareText;
    StrCompAnsiStringProc := @StrCompAnsi;
    StrICompAnsiStringProc := @AnsiStrIComp;
    StrLCompAnsiStringProc := @AnsiStrLComp;
    StrLICompAnsiStringProc := @AnsiStrLIComp;
    StrLowerAnsiStringProc := @AnsiStrLower;
    StrUpperAnsiStringProc := @AnsiStrUpper;

    Unicode2AnsiMoveProc := @Unicode2AnsiMove;
    Ansi2UnicodeMoveProc := @Ansi2UnicodeMove;
    UpperUnicodeStringProc := @UpperUnicodeString;
    LowerUnicodeStringProc := @LowerUnicodeString;
    CompareUnicodeStringProc := @CompareUnicodeString;
    CompareTextUnicodeStringProc := @CompareTextUnicodeString;
    GetStandardCodePageProc := @GetStandardCodePage;
    CodePointLengthProc := @CodePointLength;
  end;
  SetUnicodeStringManager(CWideStringManager);
end;

{$endif}

procedure UnloadICU;
begin
  if hlibICUi18n <> 0 then
  begin
    if DefColl <> nil then
      ucol_close(DefColl);
    UnloadLibrary(hlibICUi18n);
    hlibICUi18n := 0;
  end;
  if hlibICU <> 0 then
  begin
    if DefConv <> nil then
      ucnv_close(DefConv);
    if LastConv <> nil then
      ucnv_close(LastConv);
    UnloadLibrary(hlibICU);
    hlibICU:=0;
  end;
end;

procedure LoadICU;
var
  LibVer: ansistring;

  function _GetProc(const Name: AnsiString; out ProcPtr; hLib: TLibHandle = 0): boolean;
  var
    P: pointer;
  begin
    if hLib = 0 then
      hLib := hlibICU;
    P := GetProcedureAddress(hlib, Name + LibVer);
    if P = nil then
    begin
      // unload lib on failure
      UnloadICU;
      Result := False;
    end else
    begin
      pointer(ProcPtr) := P;
      Result := True;
    end;
  end;

const
  ICUver: array [1..9] of ansistring = ('3_8', '4_2', '44', '46', '48', '50', '51', '53', '55');
  TestProcName = 'ucnv_open';

var
  I: longint;
  S: ansistring;
begin
  hlibICU := LoadLibrary('libicuuc.so');
  hlibICUi18n := LoadLibrary('libicui18n.so');
  if (hlibICU = 0) or (hlibICUi18n = 0) then
  begin
    UnloadICU;
    AndroidLog(alWarn, 'Cannot load libicuuc.so or libicui18n.so. WideString conversion will fail for special UTF-8 characters');
    Exit;
  end;
  // Finding ICU version using known versions table
  for I := High(ICUver) downto Low(ICUver) do
  begin
    S := '_' + ICUver[I];
    if GetProcedureAddress(hlibICU, TestProcName + S) <> nil then
    begin
      LibVer := S;
      AndroidLog(alInfo, 'Found libicuuc.so version ' + LibVer);
      Break;
    end;
  end;

  if LibVer = '' then
  begin
    // Finding unknown ICU version
    Val(ICUver[High(ICUver)], I);
    repeat
      Inc(I);
      Str(I, S);
      S := '_'  + S;
      if GetProcedureAddress(hlibICU, TestProcName + S) <> nil then
      begin
        LibVer := S;
        AndroidLog(alInfo, 'Found libicuuc.so version (by looping) ' + LibVer);
        Break;
      end;
    until I >= 100;
  end;

  if LibVer = '' then
  begin
    // Trying versionless name
    if GetProcedureAddress(hlibICU, TestProcName) = nil then
    begin
      // Unable to get ICU version
      UnloadICU;
      AndroidLog(alWarn, 'Cannot use libicuuc.so --- no versioned ucnv_open found, and unversioned ucnv_open not available. . WideString conversion will fail for special UTF-8 characters');
      Exit;
    end;
  end;

  if not _GetProc('ucnv_open', ucnv_open) then
    Exit;
  if not _GetProc('ucnv_close', ucnv_close) then
    Exit;
  if not _GetProc('ucnv_setSubstChars', ucnv_setSubstChars) then
    Exit;
  if not _GetProc('ucnv_setFallback', ucnv_setFallback) then
    Exit;
  if not _GetProc('ucnv_fromUChars', ucnv_fromUChars) then
    Exit;
  if not _GetProc('ucnv_toUChars', ucnv_toUChars) then
    Exit;
  if not _GetProc('u_strToUpper', u_strToUpper) then
    Exit;
  if not _GetProc('u_strToLower', u_strToLower) then
    Exit;
  if not _GetProc('u_strCompare', u_strCompare) then
    Exit;
  if not _GetProc('u_strCaseCompare', u_strCaseCompare) then
    Exit;

  if not _GetProc('u_errorName', u_errorName) then
    Exit;

  if not _GetProc('ucol_open', ucol_open, hlibICUi18n) then
    Exit;
  if not _GetProc('ucol_close', ucol_close, hlibICUi18n) then
    Exit;
  if not _GetProc('ucol_strcoll', ucol_strcoll, hlibICUi18n) then
    Exit;
  if not _GetProc('ucol_setStrength', ucol_setStrength, hlibICUi18n) then
    Exit;
end;

procedure InitializeAndroidCWString;
begin
  DefaultSystemCodePage := GetStandardCodePage(scpAnsi);
  DefaultUnicodeCodePage := CP_UTF16;
  LoadICU;
  SetCWideStringManager;
  SetStdIOCodePages;
end;

finalization
  UnloadICU;
end.
