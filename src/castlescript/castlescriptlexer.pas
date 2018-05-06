{
  Copyright 2001-2018 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ @abstract(Lexer for CastleScript language, see
  [https://castle-engine.io/castle_script.php].)

  For specification of tokens that this lexer understands,
  see documentation of CastleScriptParser unit. }

unit CastleScriptLexer;

{$I castleconf.inc}

interface

uses CastleUtils, CastleScript, SysUtils, Math;

type
  TToken = (tokEnd,
    tokInteger, {< Value of constant integer will be in w TCasScriptLexer.TokenInteger. }
    tokFloat, {< Value of constant float will be in w TCasScriptLexer.TokenFloat. }
    tokBoolean, {< Value of constant boolean will be in w TCasScriptLexer.TokenBoolean. }
    tokString, {< Value of constant string will be in w TCasScriptLexer.TokenString. }

    tokIdentifier, {< Identifier will be in TCasScriptLexer.TokenString. }
    tokFuncName, {< Function class of given function will be in TCasScriptLexer.TokenFunctionClass. }
    tokFunctionKeyword,

    tokMinus, tokPlus,

    tokMultiply, tokDivide, tokPower, tokModulo,

    tokGreater, tokLesser, tokGreaterEqual, tokLesserEqual, tokEqual, tokNotEqual,

    tokLParen, tokRParen,
    tokLQaren, tokRQaren,
    tokComma, tokSemicolon, tokAssignment);

  TCasScriptLexer = class
  private
    FToken: TToken;
    FTokenInteger: Int64;
    FTokenFloat: Float;
    FTokenBoolean: boolean;
    FTokenString: string;
    FTokenFunctionClass: TCasScriptFunctionClass;

    FTextPos: Integer;
    FText: string;
  public
    property Token: TToken read FToken;

    property TokenInteger: Int64 read FTokenInteger;
    property TokenFloat: Float read FTokenFloat;
    property TokenString: string read FTokenString;
    property TokenBoolean: boolean read FTokenBoolean;
    property TokenFunctionClass: TCasScriptFunctionClass read FTokenFunctionClass;

    { Position of lexer in the @link(Text) string. }
    property TextPos: Integer read FTextPos;

    { Text that this lexer reads. }
    property Text: string read FText;

    { NextToken moves to next token (updating fields @link(Token),
      and eventually TokenFloat, TokenString and TokenFunctionClass)
      and returns the value of field @link(Token).

      When @link(Token) is tokEnd, then NextToken doesn't do anything,
      i.e. @link(Token) will remain tokEnd forever.

      @raises ECasScriptLexerError }
    function NextToken: TToken;

    constructor Create(const AText: string);

    { Current token textual description. Useful mainly for debugging lexer. }
    function TokenDescription: string;

    { Check is current token Tok, eventually rise parser error.
      This is an utility for parser.

      @raises(ECasScriptParserError
        if current Token doesn't match required Tok.) }
    procedure CheckTokenIs(Tok: TToken);
  end;

  { A common class for ECasScriptLexerError and ECasScriptParserError }
  ECasScriptSyntaxError = class(ECasScriptError)
  private
    FLexerTextPos: Integer;
    FLexerText: string;
  public
    { Those things are copied from Lexer at exception creation.
      We do not copy reference to Lexer since this would be too dangerous
      in usual situation (you would have to be always sure that you will
      not access it before you Freed it; too troublesome, usually) }
    property LexerTextPos: Integer read FLexerTextPos;
    property LexerText: string read FLexerText;
    constructor Create(Lexer: TCasScriptLexer; const S: string);
    constructor CreateFmt(Lexer: TCasScriptLexer; const S: string;
      const Args: array of const);
  end;

  ECasScriptLexerError = class(ECasScriptSyntaxError);

  ECasScriptParserError = class(ECasScriptSyntaxError);

implementation

uses StrUtils,
  CastleStringUtils;

function Int64Power(Base: Integer; Power: Cardinal): Int64;
begin
  Result := 1;
  while Power > 0 do
  begin
    Result := Result * Base;
    Dec(Power);
  end;
end;

constructor TCasScriptLexer.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FTextPos := 1;
  NextToken;
end;

function TCasScriptLexer.NextToken: TToken;
const
  WhiteChars = [' ', #9, #10, #13];
  Digits = ['0'..'9'];
  Letters = ['a'..'z', 'A'..'Z', '_'];

  procedure OmitWhiteSpace;
  begin
    while SCharIs(Text, TextPos, whiteChars) do
      Inc(FTextPos);
    if SCharIs(Text, TextPos, '{') then
    begin
      while Text[TextPos] <> '}' do
      begin
        Inc(FTextPos);
        if TextPos > Length(Text) then
          raise ECasScriptLexerError.Create(Self, 'Unfinished comment');
      end;
      Inc(FTextPos);
      OmitWhiteSpace; { recusively omit the rest of whitespace }
    end;
  end;

  function ReadSimpleToken: boolean;
  const
    { kolejnosc w ToksStrs MA znaczenie - pierwszy zostanie dopasowany string dluzszy,
      wiec aby Lexer pracowal zachlannnie stringi dluzsze musza byc pierwsze. }
    ToksStrs: array [0..18] of string=
     ('<>', '<=', '>=', '<', '>', '=', '+', '-', '*', '/', ',',
      '(', ')', '^', '[', ']', '%', ';', ':=');
    ToksTokens: array[0..High(ToksStrs)] of TToken =
     (tokNotEqual, tokLesserEqual, tokGreaterEqual, tokLesser, tokGreater,
      tokEqual, tokPlus, tokMinus, tokMultiply, tokDivide, tokComma, tokLParen, tokRParen,
      tokPower, tokLQaren, tokRQaren, tokModulo, tokSemicolon, tokAssignment);
  var I: integer;
  begin
    for I := 0 to High(ToksStrs) do
      if Copy(Text, TextPos, Length(ToksStrs[I])) = ToksStrs[I] then
      begin
        FToken := ToksTokens[I];
        Inc(FTextPos, Length(ToksStrs[I]));
        Result := true;
        Exit;
      end;
    Result := false;
  end;

  { Read a string, to a tokString token.
    Read from current TexPos.
    Update FToken and FTokenString, and advance TextPos, and return true
    if success.

    Results in false if we're not standing at an apostrophe now. }
  function ReadString: boolean;
  var
    NextApos: Integer;
  begin
    Result := Text[FTextPos] = '''';
    if not Result then
      Exit;

    FToken := tokString;
    FTokenString := '';

    repeat
      NextApos := PosEx('''', Text, FTextPos + 1);
      if NextApos = 0 then
        raise ECasScriptLexerError.Create(Self, 'Unfinished string');
      FTokenString := FTokenString + CopyPos(Text, FTextPos + 1, NextApos - 1);
      FTextPos := NextApos + 1;

      if SCharIs(Text, FTextPos, '''') then
        FTokenString := FTokenString + ''''
      else
        Break;
    until false;
  end;

  { Read a number, to a tokFloat or tokInteger token.
    Read from current TexPos.
    Update FToken and FTokenFloat, and advance TextPos, and return true
    if success.

    Results in false if we're not standing at a digit now. }
  function ReadNumber: boolean;
  var
    DigitsCount: cardinal;
    Val: Int64;
  begin
    Result := Text[FTextPos] in Digits;
    if not Result then
      Exit;

    { Assume it's an integer token at first, until we will encounter the dot. }

    Ftoken := TokInteger;
    FTokenInteger := DigitAsByte(Text[FTextPos]);
    Inc(FTextPos);
    while SCharIs(Text, FTextPos, Digits) do
    begin
      FTokenInteger := 10 * FTokenInteger + DigitAsByte(Text[FTextPos]);
      Inc(FTextPos);
    end;

    if SCharIs(Text, FTextPos, '.') then
    begin
      { So it's a float. Read fractional part. }
      FToken := tokFloat;
      FTokenFloat := FTokenInteger;

      Inc(FTextPos);
      if not SCharIs(Text, FTextPos, Digits) then
        raise ECasScriptLexerError.Create(Self, 'Digit expected');
      DigitsCount := 1;
      Val := DigitAsByte(Text[FTextPos]);
      Inc(FTextPos);
      while SCharIs(Text, FTextPos, Digits) do
      begin
        Val := 10 * Val + DigitAsByte(Text[FTextPos]);
        Inc(DigitsCount);
        Inc(FTextPos);
      end;
      FTokenFloat := FTokenFloat + (Val / Int64Power(10, DigitsCount));
    end;
  end;

  function ReadIdentifier: string;
  { czytaj identyfikator - to znaczy, czytaj nazwe zmiennej co do ktorej nie
    jestesmy pewni czy nie jest przypadkiem nazwa funkcji. Uwaga - powinien
    zbadac kazdy znak, poczynajac od Text[FTextPos], czy rzeczywiscie
    nalezy do IdentChars.

    Always returns non-empty string (length >= 1) }
  const IdentStartChars = Letters;
        IdentChars = IdentStartChars + Digits;
  var StartPos: integer;
  begin
    if not (Text[FTextPos] in IdentStartChars) then
      raise ECasScriptLexerError.CreateFmt(Self,
        'Invalid character "%s" not allowed in CastleScript', [Text[FTextPos]]);
    StartPos := FTextPos;
    Inc(FTextPos);
    while SCharIs(Text, FTextPos, IdentChars) do
      Inc(FTextPos);
    Result := CopyPos(Text, StartPos, FTextPos-1);
  end;

const
  FloatConsts: array [0..1] of string = ('pi', 'enat');
  FloatConstsValues: array [0..High(FloatConsts)] of float = (pi, enatural);
  BooleanConsts: array [0..1] of string = ('false', 'true');
  BooleanConstsValues: array [0..High(BooleanConsts)] of boolean = (false, true);
  IntConsts: array [0..19] of string = (
    'ACTION_KEY_F1',
    'ACTION_KEY_F2',
    'ACTION_KEY_F3',
    'ACTION_KEY_F4',
    'ACTION_KEY_F5',
    'ACTION_KEY_F6',
    'ACTION_KEY_F7',
    'ACTION_KEY_F8',
    'ACTION_KEY_F9',
    'ACTION_KEY_F10',
    'ACTION_KEY_F11',
    'ACTION_KEY_F12',
    'ACTION_KEY_HOME',
    'ACTION_KEY_END',
    'ACTION_KEY_PGUP',
    'ACTION_KEY_PGDN',
    'ACTION_KEY_UP',
    'ACTION_KEY_DOWN',
    'ACTION_KEY_LEFT',
    'ACTION_KEY_RIGHT'
  );
  IntConstsValues: array [0..High(IntConsts)] of Integer = (
    1, 2, 3, 4, 5, 6, 7, 8, 9,10,
   11,12,13,14,15,16,17,18,19,20 );
var
  P: integer;
  FC: TCasScriptFunctionClass;
begin
  OmitWhiteSpace;

  if TextPos > Length(Text) then
    FToken := tokEnd
  else
  begin
    if not ReadString then
      if not ReadNumber then
        if not ReadSimpleToken then
        begin
          { It's something that *may* be an identifier.
            Unless it matches some keyword, built-in function or constant. }
          FToken := tokIdentifier;
          FTokenString := ReadIdentifier;

          { Maybe it's tokFunctionKeyword (the only keyword for now) }
          if FToken = tokIdentifier then
          begin
            if SameText(FTokenString, 'function') then
            begin
              FToken := tokFunctionKeyword;
            end;
          end;

          { Maybe it's tokFuncName }
          if FToken = tokIdentifier then
          begin
            FC := FunctionHandlers.SearchFunctionShortName(FTokenString);
            if FC <> nil then
            begin
              FToken := tokFuncName;
              FTokenFunctionClass := FC;
            end;
          end;

          { Maybe it's a named constant float }
          if FToken = tokIdentifier then
          begin
            P := ArrayPosText(FTokenString, FloatConsts);
            if P >= 0 then
            begin
              FToken := tokFloat;
              FTokenFloat := FloatConstsValues[P];
            end;
          end;

          { Maybe it's a named constant boolean }
          if FToken = tokIdentifier then
          begin
            P := ArrayPosText(FTokenString, BooleanConsts);
            if P >= 0 then
            begin
              FToken := tokBoolean;
              FTokenBoolean := BooleanConstsValues[P];
            end;
          end;

          { Maybe it's a named constant integer }
          if FToken = tokIdentifier then
          begin
            P := ArrayPosText(FTokenString, IntConsts);
            if P >= 0 then
            begin
              FToken := tokInteger;
              FTokenInteger := IntConstsValues[P];
            end;
          end;
        end;
 end;
 Result := Token;
end;

const
  TokenShortDescription: array [TToken] of string =
  ( 'end of stream',
    'integer',
    'float',
    'boolean',
    'string',
    'identifier',
    'built-in function',
    'function',
    '-', '+',
    '*', '/', '^', '%',
    '>', '<', '>=', '<=', '=', '<>',
    '(', ')',
    '[', ']',
    ',', ';', ':=');

function TCasScriptLexer.TokenDescription: string;
begin
  Result := TokenShortDescription[Token];
  case Token of
    tokInteger: Result := Result + Format(' %d', [TokenInteger]);
    tokFloat: Result := Result + Format(' %g', [TokenFloat]);
    tokBoolean: Result := Result + Format(' %s', [BoolToStr(TokenBoolean, true)]);
    tokString: Result := Result + Format(' ''%s''', [TokenString]);
    tokIdentifier: Result := Result + Format(' %s', [TokenString]);
    tokFuncName: Result := Result + Format(' %s', [TokenFunctionClass.Name]);
  end;
end;

procedure TCasScriptLexer.CheckTokenIs(Tok: TToken);
begin
  if Token <> Tok then
    raise ECasScriptParserError.CreateFmt(Self,
      'Expected "%s", but got "%s"',
      [ TokenShortDescription[Tok], TokenDescription ]);
end;

{ ECasScriptSyntaxError --------------------------------------- }

constructor ECasScriptSyntaxError.Create(Lexer: TCasScriptLexer; const S: string);
begin
 inherited Create(S);
 FLexerTextPos := Lexer.TextPos;
 FLexerText := Lexer.Text;
end;

constructor ECasScriptSyntaxError.CreateFmt(Lexer: TCasScriptLexer; const S: string;
  const Args: array of const);
begin
 Create(Lexer, Format(S, Args))
end;

end.
