{
  Copyright 2001-2008 Michalis Kamburelis.

  This file is part of "Kambi VRML game engine".

  "Kambi VRML game engine" is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  "Kambi VRML game engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with "Kambi VRML game engine"; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
}

{ Base KambiScript structures: values, functions, expressions.

  It is designed to be extendable, so you can add new TKamScriptValue
  descendants and new TKamScriptFunction descendants, and register
  their handlers in FunctionHandlers instance (TKamScriptFunctionHandlers).

  Using structures here you can also build KambiScript expressions
  by Pascal code (that is, you don't have to parse them). For example
  this is an expression that calculates @code(sin(3) + 10 + 1):

@longcode(#
  Expr := TKamScriptAdd.Create([
      TKamScriptSin.Create([TKamScriptFloat.Create(3)]),
      TKamScriptFloat.Create(10),
      TKamScriptFloat.Create(1)
    ]);
#)

  You can then call @code(Expr.Execute) to calculate such expression.

  To make a variable in the expression, just create and remember a
  TKamScriptFloat instance first, and then change it's value freely between
  @code(Expr.Execute) calls. For example

@longcode(#
  MyVariable := TKamScriptFloat.Create(3);
  Expr := TKamScriptAdd.Create([
      TKamScriptSin.Create([MyVariable]),
      TKamScriptFloat.Create(10),
      TKamScriptFloat.Create(1)
    ]);

  Writeln((Expr.Execute as TKamStringFloat).Value); // calculate "sin(3) + 10 + 1"

  MyVariable.Value := 4;
  Writeln((Expr.Execute as TKamStringFloat).Value); // calculate "sin(4) + 10 + 1"

  MyVariable.Value := 5;
  Writeln((Expr.Execute as TKamStringFloat).Value); // calculate "sin(5) + 10 + 1"
#)

  Note that generally each TKamScriptExpression owns it's children
  expressions, so they will be automatically freed when parent is freed.
  Also, the values returned by Execute are owned by expression.
  So you can simply free whole thing by @code(Expr.Free).

  If you're want to parse KambiScript expression from a text
  file, see KambiScriptParser.
}
unit KambiScript;

interface

uses SysUtils, Math, Contnrs, KambiUtils, KambiClassUtils;

{$define read_interface}

type
  { }
  TKamScriptValue = class;

  EKamScriptError = class(Exception);
  EKamAssignValueError = class(EKamScriptError);

  TKamScriptExpression = class
  public
    (*Execute and calculate this expression.

      Returned value is owned by this object. Which should be comfortable
      for you usually, as you do not have to worry about freeing it.
      Also, it allows us to make various optimizations to avoid
      creating/destroying lots of temporary TKamScriptExpression
      instances during calculation of complex expression.

      The disadvantage of this is that returned object value is valid
      only until you executed this same expression again,
      or until you freed this expression. If you need to remember the
      execute result for longer, you have to copy it somewhere.
      For example you can do

@longCode(#
  { This will always work, thanks to virtual TKamScriptValue.Create
    and AssignValue methods. }
  Copy := TKamScriptValue(ReturnedValue.ClassType).Create;
  Copy.AssignValue(ReturnedValue);
#)

      Execute is guaranteed to raise an exception if some
      calculation fails, e.g. if expression will be 'ln(-3)'.
      Stating it directly, Execute may even call Math.ClearExceptions(true)
      if it is needed to force generating proper exceptions.

      This ensures that we can safely execute even invalid expressions
      (like 'ln(-3)') and get reliable exceptions.*)
    function Execute: TKamScriptValue; virtual; abstract;

    { Try to execute expression, or return @nil if an error within
      expression. "Error within expression" means that
      any exception occured while calculating expression. }
    function TryExecute: TKamScriptValue;

    { Call Free, but only if this is not TKamScriptValue with
      OwnedByParentExpression = false. (This cannot be implemented
      cleanly, as virtual procedure, since it must work when Self is @nil,
      and then virtual method table is not available of course.) }
    procedure FreeByParentExpression;
  end;

  TObjectsListItem_1 = TKamScriptExpression;
  {$I objectslist_1.inc}
  TKamScriptExpressionsList = class(TObjectsList_1)
    procedure FreeContentsByParentExpression;
  end;

  TKamScriptValue = class(TKamScriptExpression)
  private
    FOwnedByParentExpression: boolean;
    FName: string;
    FValueAssigned: boolean;
  public
    constructor Create; virtual;
    function Execute: TKamScriptValue; override;

    property OwnedByParentExpression: boolean
      read FOwnedByParentExpression write FOwnedByParentExpression
      default true;

    { Name of this value, or '' if not named.
      Named value can be recognized in expressions by KambiScriptParser. }
    property Name: string read FName write FName;

    { Assign value from Source to Self.
      @raises(EKamAssignValueError if assignment is not possible
      because types don't match.) }
    procedure AssignValue(Source: TKamScriptValue); virtual; abstract;

    { Set to @true on each assign to Value. You can reset it at any time
      to @false.

      This allows the caller to know which variables were
      assigned during script execution, which is useful if changes to
      KambiScript variables should be propagated to some other things
      after the script finished execution. This is essential for behavior
      in VRML Script node.

      Descendants note: you have to set this to @true in SetValue. }
    property ValueAssigned: boolean read FValueAssigned write FValueAssigned
      default false;
  end;

  TKamScriptValueClass = class of TKamScriptValue;

  TObjectsListItem_2 = TKamScriptValue;
  {$I objectslist_2.inc}
  TKamScriptValuesList = TObjectsList_2;

  TKamScriptFloat = class;

  TKamScriptInteger = class(TKamScriptValue)
  private
    class procedure HandleAdd(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleSubtract(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleNegate(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    class procedure HandleMultiply(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleDivide(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleModulo(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandlePower(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    class procedure HandleSqr(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleSgn(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleAbs(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    class procedure HandleGreater(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLesser(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleGreaterEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLesserEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleNotEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    class procedure ConvertFromInt(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromFloat(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromBool(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromString(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    FPromoteToFloat: TKamScriptFloat;

    FValue: Int64;
    procedure SetValue(const AValue: Int64);
  public
    { Comfortable constructor to set initial Value.
      Note that the inherited constructor without parameters is
      also fine to use, it will set value to zero. }
    constructor Create(AValue: Int64);
    constructor Create; override;
    destructor Destroy; override;

    property Value: Int64 read FValue write SetValue;

    procedure AssignValue(Source: TKamScriptValue); override;

    { Returns this integer promoted to float.

      This object is kept and owned by this TKamScriptInteger instance,
      so it's valid as long as this TKamScriptInteger instance is valid.
      This allows you to safely use this (since you may have to return
      PromoteToFloat as return value of some Execute expressions,
      so it desirable that it's valid object reference). }
    function PromoteToFloat: TKamScriptFloat;
  end;

  TKamScriptFloat = class(TKamScriptValue)
  private
    class procedure HandleAdd(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleSubtract(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleMultiply(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleDivide(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleNegate(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleModulo(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleSin(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleCos(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleTan(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleCotan(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleArcSin(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleArcCos(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleArcTan(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleArcCotan(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleSinh(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleCosh(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleTanh(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleCotanh(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLog2(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLn(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLog(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandlePower2(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleExp(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandlePower(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleSqr(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleSqrt(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleSgn(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleAbs(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleCeil(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleFloor(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleGreater(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLesser(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleGreaterEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLesserEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleNotEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    class procedure ConvertFromInt(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromFloat(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromBool(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromString(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    FValue: Float;
    procedure SetValue(const AValue: Float);
  public
    { Comfortable constructor to set initial Value.
      Note that the inherited constructor without parameters is
      also fine to use, it will set value to zero. }
    constructor Create(AValue: Float);

    constructor Create; override;

    property Value: Float read FValue write SetValue;

    procedure AssignValue(Source: TKamScriptValue); override;
  end;

  TKamScriptBoolean = class(TKamScriptValue)
  private
    class procedure HandleOr(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleAnd(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleNot(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    class procedure HandleGreater(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLesser(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleGreaterEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLesserEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleNotEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    class procedure ConvertFromInt(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromFloat(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromBool(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromString(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    FValue: boolean;
    procedure SetValue(const AValue: boolean);
  public
    { Comfortable constructor to set initial Value.
      Note that the inherited constructor without parameters is
      also fine to use, it will set value to zero. }
    constructor Create(AValue: boolean);

    constructor Create; override;

    property Value: boolean read FValue write SetValue;

    procedure AssignValue(Source: TKamScriptValue); override;
  end;

  TKamScriptString = class(TKamScriptValue)
  private
    class procedure HandleAdd(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    class procedure HandleGreater(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLesser(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleGreaterEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleLesserEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure HandleNotEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    class procedure ConvertFromInt(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromFloat(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromBool(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
    class procedure ConvertFromString(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);

    FValue: string;
    procedure SetValue(const AValue: string);
  public
    { Comfortable constructor to set initial Value.
      Note that the inherited constructor without parameters is
      also fine to use, it will set value to zero. }
    constructor Create(AValue: string);

    constructor Create; override;

    property Value: string read FValue write SetValue;

    procedure AssignValue(Source: TKamScriptValue); override;
  end;

  TKamScriptFunction = class(TKamScriptExpression)
  private
    FArgs: TKamScriptExpressionsList;
    LastExecuteResult: TKamScriptValue;
    ParentOfLastExecuteResult: boolean;
  protected
    { Used by constructor to check are args valid.
      @raises(EKamScriptFunctionArgumentsError on invalid Args passed to
      function.) }
    procedure CheckArguments; virtual;
  public
    { Constructor initializing Args from given TKamScriptExpressionsList.
      AArgs list contents is copied, i.e. AArgs refence is not
      stored or freed by TKamScriptFunction. But items on AArags are not copied
      recursively, we copy references from AArags items, and so we become
      their owners.

      @raises(EKamScriptFunctionArgumentsError if you specified invalid
        number of arguments for this function.)
    }
    constructor Create(AArgs: TKamScriptExpressionsList); overload;
    constructor Create(const AArgs: array of TKamScriptExpression); overload;
    destructor Destroy; override;

    { Long function name for user. This is possibly with spaces,
      parenthesis and other funny characters. It will be used in
      error messages and such to describe this function. }
    class function Name: string; virtual; abstract;

    { Short function name, for the parser.
      This is the name of the function for use in expressions
      like "function_name(arg_1, arg_2 ... , arg_n)".

      This can be empty string ('') if no such name for this function exists,
      then the logic to parse this function expressions must be somehow
      built in the parser (for example, operators use this: they are
      just normal functions, TKamScriptFunction, with ShortName = ''
      and special support in the parser). }
    class function ShortName: string; virtual; abstract;

    { Function name when used as an infix operator.

      Empty string ('') if no such name for this function.
      This is returned by default implementation of this in this class.

      This does require cooperation from the parser to actually work,
      that is you cannot simply define new operators by
      registering new TKamScriptFunction with InfixOperatorName <> ''.
      For now.

      Note that at least one of ShortName and InfixOperatorName
      must not be empty.

      The only exception is the TKamScriptNegate function, that is neither
      infix operator nor a usual function that must be specified
      as "function_name(arguments)". So this is an exception,
      and if there will be a need, I shall fix this (probably
      by introducing some third field, like PrefixOperatorName ?)

      Note 2 things:

      @orderedList(
        @item(
          Function that can be used as infix operator (i.e. has
          InfixOperatorName <> '') is not necessary binary operator,
          i.e. InfixOperatorName <> ''  does not determine the value of
          ArgsCount. This way I was able to define infix operators
          +, -, * etc. that take any number of arguments and operators
          like ^ and > that always take 2 arguments.)

        @item(
          Function may have both ShortName <> '' and InfixOperatorName <> ''.
          E.g. TKamScriptPower can be used as "Power(3, 1.5)" or "3 ^ 1.5".)
      ) }
    class function InfixOperatorName: string; virtual;

    { Function arguments. Don't modify this list after function is created
      (although you can modify values inside arguments). }
    property Args: TKamScriptExpressionsList read FArgs;

    function Execute: TKamScriptValue; override;
  end;

  TKamScriptFunctionClass = class of TKamScriptFunction;

  { Calculate result on given function arguments Arguments.
    Place result in AResult.

    The current function is not passed here --- you don't need it
    (you already get a list of calculated Arguments, and you should
    register different procedures for different TKamScriptFunction classes,
    so you know what operation on arguments should be done).

    If needed, previous value of AResult should be freed and new created.
    If current AResult is <> nil and it's of appropriate class,
    you may also reuse it and only change it's fields
    (this is helpful, to avoid many creations/destroying
    of class instances while calculating an expression many times).
    CreateValueIfNeeded may be helpful for implementing this. }
  TKamScriptFunctionHandler = procedure (
    const Arguments: array of TKamScriptValue;
    var AResult: TKamScriptValue;
    var ParentOfResult: boolean) of object;

  TKamScriptSequence = class(TKamScriptFunction)
  private
    class procedure HandleSequence(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
  public
    class function Name: string; override;
    class function ShortName: string; override;
    class function InfixOperatorName: string; override;
  end;

  { KambiScript assignment operator. This is a special function,
    that must have settable TKamScriptValue as it's 1st argument.

    For now, we check TKamScriptValue.Name <> '', this determines if
    this is settable (in the future, more explicit check may be done). }
  TKamScriptAssignment = class(TKamScriptFunction)
  private
    class procedure HandleAssignment(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
  protected
    procedure CheckArguments; override;
  public
    class function Name: string; override;
    class function ShortName: string; override;
    class function InfixOperatorName: string; override;
  end;

  TKamScriptValueClassArray = array of TKamScriptValueClass;

  TKamScriptRegisteredHandler = class
  private
    FHandler: TKamScriptFunctionHandler;
    FFunctionClass: TKamScriptFunctionClass;
    FArgumentClasses: TKamScriptValueClassArray;
    FVariableArgumentsCount: boolean;
  public
    constructor Create(
      AHandler: TKamScriptFunctionHandler;
      AFunctionClass: TKamScriptFunctionClass;
      const AArgumentClasses: TKamScriptValueClassArray;
      const AVariableArgumentsCount: boolean);
    property Handler: TKamScriptFunctionHandler read FHandler;
    property FunctionClass: TKamScriptFunctionClass read FFunctionClass;
    property ArgumentClasses: TKamScriptValueClassArray read FArgumentClasses;

    { Is the handler able to receive any number of arguments.

      If yes, then the last argument class
      may be repeated any number of times (but must occur
      at least once). That is, the ArgumentClasses array
      dictates the required arguments, and more arguments are allowed.
      Note that this means that at least one argument
      must be allowed (we have to know the argument class that can
      be repeated at the end), otherwise the handler will not be able to receive
      variable number of arguments anyway. }
    property VariableArgumentsCount: boolean read FVariableArgumentsCount;
  end;

  { This specifies for each type combination (array of TKamScriptValue classes)
    and for each function (TKamScriptFunction class) how they should
    be handled. You can think of this as a table that has a handler
    for each possible TKamScriptValue sequence and TKamScriptFunction
    combination.

    The idea is to allow programmer to extend KambiScipt by

    @orderedList(
      @item(Defining new types of values for KambiScript:
        add new TKamScriptValue class, and create handlers for known
        functions to handle this type.

        It may be comfortable to place these handlers as private methods
        within your new TKamScriptValue descendant, although this is your
        private decision.)

      @item(Defining new functions for KambiScript:
        add new TKamScriptFunction class, and create handlers for known
        values to be handled by this function.

        It may be comfortable to place these handlers as private methods
        within your new TKamScriptFunction descendant, although this is your
        private decision.)
    )

    You have a guarantee that every registered here Handler will be called
    only with AFunction of registstered type and all Arguments
    matching the array of registered types and satisfying
    VariableArgumentsCount setting.

    As a bonus, this also provides a list of all usable function classes.
    That's because you have to register at least one handler for each
    TKamScriptFunction descendant to make this function actually usable,
    so we know about it here. }
  TKamScriptFunctionHandlers = class
  private
    { This is a list of another TObjectList lists.

      Each nested list has only TKamScriptRegisteredHandler items.
      It always has at least one item.
      Each nested list has only equal FunctionClass values. }
    FHandlersByFunction: TObjectList;

    function SearchFunctionClass(
      FunctionClass: TKamScriptFunctionClass;
      out FunctionIndex: Integer;
      out HandlersByArgument: TObjectList): boolean; overload;
    function SearchFunctionClass(
      FunctionClass: TKamScriptFunctionClass;
      out HandlersByArgument: TObjectList): boolean; overload;

    function SearchArgumentClasses(
      HandlersByArgument: TObjectList;
      const ArgumentClasses: TKamScriptValueClassArray;
      out ArgumentIndex: Integer;
      out Handler: TKamScriptRegisteredHandler): boolean; overload;
    function SearchArgumentClasses(
      HandlersByArgument: TObjectList;
      const ArgumentClasses: TKamScriptValueClassArray;
      out Handler: TKamScriptRegisteredHandler): boolean; overload;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegisterHandler(
      AHandler: TKamScriptFunctionHandler;
      AFunctionClass: TKamScriptFunctionClass;
      const AArgumentClasses: array of TKamScriptValueClass;
      const AVariableArgumentsCount: boolean);

    { Search for function class with matching ShortName.
      Returns @nil if not found. }
    function SearchFunctionShortName(const AShortName: string): TKamScriptFunctionClass;
  end;

  EKamScriptFunctionArgumentsError = class(EKamScriptError);
  EKamScriptFunctionNoHandler = class(EKamScriptError);

  { KambiScript function definition.

    Not to be confused with TKamScriptFunction: TKamScriptFunction is
    an internal, built-in function or operator. This class represents
    functions defined by user. }
  TKamScriptFunctionDefinition = class
  private
    FName: string;
    FParameters: TKamScriptValuesList;
    FBody: TKamScriptExpression;
  public
    constructor Create;
    destructor Destroy; override;

    property Name: string read FName write FName;

    { List of function parameters.

      Note that they are also referenced inside function Expression,
      so you simply change them to set value of this parameter within
      whole function body.

      These are always fresh variables, not referenced anywhere outside
      of Body. This means that they are owned (always, regardless of
      OwnedByParentExpression) by this class. }
    property Parameters: TKamScriptValuesList read FParameters;

    { Function body. }
    property Body: TKamScriptExpression read FBody write FBody;
  end;

  TObjectsListItem_3 = TKamScriptFunctionDefinition;
  {$I objectslist_3.inc}
  TKamScriptFunctionDefinitionsList = class(TObjectsList_3)
    function IndexOf(const FunctionName: string): Integer;
  end;

  EKamScriptMissingFunction = class(EKamScriptError);

  TKamScriptProgram = class
  private
    FFunctions: TKamScriptFunctionDefinitionsList;
  public
    constructor Create;
    destructor Destroy; override;

    property Functions: TKamScriptFunctionDefinitionsList read FFunctions;

    { Execute a user-defined function (from Functions list of this program).

      @unorderedList(
        @item(Looks for given FunctionName.

          IgnoreMissingFunction says what to do in case of missing function:
          if true, it will be simply ignored (ExecuteFunction will
          silently do nothng). If false (default)
          then we will raise exception EKamScriptMissingFunction.)
        @item(Sets function parameters to given values
         (number of parameters must match, otherwise EKamScriptError).)
        @item(Finally executes function body.)
      )
    }
    procedure ExecuteFunction(const FunctionName: string;
      const Parameters: array of Float;
      const IgnoreMissingFunction: boolean = false);
  end;

var
  FunctionHandlers: TKamScriptFunctionHandlers;

{ Make sure Value is assigned and of NeededClass.
  If Value is not assigned, or is not exactly of NeededClass,
  it will be freed and new will be created. }
procedure CreateValueIfNeeded(var Value: TKamScriptValue;
  var ParentOfValue: boolean;
  NeededClass: TKamScriptValueClass);

{$undef read_interface}

implementation

uses KambiScriptMathFunctions;

{$define read_implementation}
{$I objectslist_1.inc}
{$I objectslist_2.inc}
{$I objectslist_3.inc}

{ FPC 2.2.2 has bug http://bugs.freepascal.org/view.php?id=12214
  that strongly hits calculating invalid expressions.
  This results in calls like
    gen_function "ln(x)" -10 10 0.1
    gen_function "sqrt(x)" -10 10 0.1
  to fail after a couple of "break" lines with

    gen_function: Exception EInvalidOp (at address 0x080488B5) :
    Invalid floating point operation
    An unhandled exception occurred at $080488B5 :
    EInvalidOp : Invalid floating point operation
      $080488B5  main,  line 127 of gen_function.pasprogram

  I tried to make more elegant workarounds by doing dummy fp
  operations at the end of function calculation or TryExecute, to cause
  the exception, but it just looks like EInvalidOp is never cleared by
  try..except block.

  The only workaround seems to be to use Set8087CW to mask exceptions,
  and then compare with NaN to make proper TryExecute implementation. }
{$ifdef VER2_2_2}
  {$define WORKAROUND_EXCEPTIONS_FOR_SCRIPT_EXPRESSIONS}
{$endif}

{ TKamScriptExpression ------------------------------------------------------- }

procedure TKamScriptExpression.FreeByParentExpression;
begin
  if (Self <> nil) and
      ( (not (Self is TKamScriptValue)) or
        TKamScriptValue(Self).OwnedByParentExpression ) then
    Free;
end;

function TKamScriptExpression.TryExecute: TKamScriptValue;
begin
  try
    Result := Execute;
    {$ifdef WORKAROUND_EXCEPTIONS_FOR_SCRIPT_EXPRESSIONS}
    {$I norqcheckbegin.inc}
    if (Result is TKamScriptFloat) and
       IsNan(TKamScriptFloat(Result).Value) then
      Result := nil;
    {$I norqcheckend.inc}
    {$endif}
  except
    Result := nil;
  end;
end;

{ TKamScriptExpressionsList -------------------------------------------------- }

procedure TKamScriptExpressionsList.FreeContentsByParentExpression;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
  begin
    Items[I].FreeByParentExpression;
    Items[I] := nil;
  end;
end;

{ TKamScriptValue ------------------------------------------------------------ }

constructor TKamScriptValue.Create;
begin
  inherited;
  FOwnedByParentExpression := true;
end;

function TKamScriptValue.Execute: TKamScriptValue;
begin
  { Since we own Execute result, we can simply return self here. }
  Result := Self;
end;

{ TKamScriptInteger ---------------------------------------------------------- }

constructor TKamScriptInteger.Create(AValue: Int64);
begin
  Create;
  Value := AValue;
end;

constructor TKamScriptInteger.Create;
begin
  inherited Create;
end;

destructor TKamScriptInteger.Destroy;
begin
  FPromoteToFloat.FreeByParentExpression;
  inherited;
end;

function TKamScriptInteger.PromoteToFloat: TKamScriptFloat;
begin
  if FPromoteToFloat = nil then
    FPromoteToFloat := TKamScriptFloat.Create;
  FPromoteToFloat.Value := Value;
  Result := FPromoteToFloat;
end;

class procedure TKamScriptInteger.HandleAdd(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  I: Integer;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  { The function allows only >= 1 arguments, and this handler is
    registered only for TKamScriptInteger values, so we can safely take
    the first arg as TKamScriptInteger. }
  TKamScriptInteger(AResult).Value := TKamScriptInteger(Arguments[0]).Value;
  for I := 1 to Length(Arguments) - 1 do
    TKamScriptInteger(AResult).Value :=
      TKamScriptInteger(AResult).Value + TKamScriptInteger(Arguments[I]).Value;
end;

class procedure TKamScriptInteger.HandleSubtract(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  I: Integer;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := TKamScriptInteger(Arguments[0]).Value;
  for I := 1 to Length(Arguments) - 1 do
    TKamScriptInteger(AResult).Value :=
      TKamScriptInteger(AResult).Value - TKamScriptInteger(Arguments[I]).Value;
end;

class procedure TKamScriptInteger.HandleMultiply(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  I: Integer;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := TKamScriptInteger(Arguments[0]).Value;
  for I := 1 to Length(Arguments) - 1 do
    TKamScriptInteger(AResult).Value :=
      TKamScriptInteger(AResult).Value * TKamScriptInteger(Arguments[I]).Value;
end;

class procedure TKamScriptInteger.HandleDivide(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  I: Integer;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := TKamScriptInteger(Arguments[0]).Value;
  for I := 1 to Length(Arguments) - 1 do
    TKamScriptInteger(AResult).Value :=
      TKamScriptInteger(AResult).Value div TKamScriptInteger(Arguments[I]).Value;
end;

class procedure TKamScriptInteger.HandleNegate(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := - TKamScriptInteger(Arguments[0]).Value;
end;

class procedure TKamScriptInteger.HandleModulo(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value :=
    TKamScriptInteger(Arguments[0]).Value mod
    TKamScriptInteger(Arguments[1]).Value;
end;

class procedure TKamScriptInteger.HandlePower(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  if (TKamScriptInteger(Arguments[0]).Value < 0) or
     (TKamScriptInteger(Arguments[1]).Value < 0) then
    raise EKamScriptError.Create('Power function on integer operands expects both arguments to be >= 0');

  TKamScriptInteger(AResult).Value := NatNatPower(
    TKamScriptInteger(Arguments[0]).Value,
    TKamScriptInteger(Arguments[1]).Value );
end;

class procedure TKamScriptInteger.HandleSqr(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := Sqr( TKamScriptInteger(Arguments[0]).Value );
end;

class procedure TKamScriptInteger.HandleSgn(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := Sign( TKamScriptInteger(Arguments[0]).Value );
end;

class procedure TKamScriptInteger.HandleAbs(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := Abs( TKamScriptInteger(Arguments[0]).Value );
end;

class procedure TKamScriptInteger.HandleGreater(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptInteger(Arguments[0]).Value >
    TKamScriptInteger(Arguments[1]).Value;
end;

class procedure TKamScriptInteger.HandleLesser(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptInteger(Arguments[0]).Value <
    TKamScriptInteger(Arguments[1]).Value;
end;

class procedure TKamScriptInteger.HandleGreaterEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptInteger(Arguments[0]).Value >=
    TKamScriptInteger(Arguments[1]).Value;
end;

class procedure TKamScriptInteger.HandleLesserEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptInteger(Arguments[0]).Value <=
    TKamScriptInteger(Arguments[1]).Value;
end;

class procedure TKamScriptInteger.HandleEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptInteger(Arguments[0]).Value =
    TKamScriptInteger(Arguments[1]).Value;
end;

class procedure TKamScriptInteger.HandleNotEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptInteger(Arguments[0]).Value <>
    TKamScriptInteger(Arguments[1]).Value;
end;

class procedure TKamScriptInteger.ConvertFromInt(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  if ParentOfResult then
    AResult.FreeByParentExpression else
    AResult := nil;

  AResult := Arguments[0];
  Assert(AResult is TKamScriptInteger);
  ParentOfResult := false;
end;

class procedure TKamScriptInteger.ConvertFromFloat(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  F: Float;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  { Can't use Int function, as it returns float value }

  F := TKamScriptFloat(Arguments[0]).Value;
  if F >= 0 then
    TKamScriptInteger(AResult).Value := Floor(F) else
    TKamScriptInteger(AResult).Value := Ceil(F);
end;

class procedure TKamScriptInteger.ConvertFromBool(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  BoolTo01: array [boolean] of Int64 = (0, 1);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := BoolTo01[TKamScriptBoolean(Arguments[0]).Value];
end;

class procedure TKamScriptInteger.ConvertFromString(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  try
    TKamScriptInteger(AResult).Value := StrToInt64(TKamScriptString(Arguments[0]).Value);
  except
    on E: EConvertError do
      { Change EConvertError to EKamScriptError }
      raise EKamScriptError.CreateFmt('Error when converting string "%s" to integer: %s',
        [TKamScriptString(Arguments[0]).Value, E.Message]);
  end;
end;

procedure TKamScriptInteger.AssignValue(Source: TKamScriptValue);
begin
  if Source is TKamScriptInteger then
    Value := TKamScriptInteger(Source).Value else
    raise EKamAssignValueError.CreateFmt('Assignment from %s to %s not possible', [Source.ClassName, ClassName]);
end;

procedure TKamScriptInteger.SetValue(const AValue: Int64);
begin
  FValue := AValue;
  ValueAssigned := true;
end;

{ TKamScriptFloat ------------------------------------------------------- }

constructor TKamScriptFloat.Create(AValue: Float);
begin
  Create;
  Value := AValue;
end;

constructor TKamScriptFloat.Create;
begin
  inherited Create;
end;

class procedure TKamScriptFloat.HandleAdd(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  I: Integer;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  { The function allows only >= 1 arguments, and this handler is
    registered only for TKamScriptFloat values, so we can safely take
    the first arg as TKamScriptFloat. }
  TKamScriptFloat(AResult).Value := TKamScriptFloat(Arguments[0]).Value;
  for I := 1 to Length(Arguments) - 1 do
    TKamScriptFloat(AResult).Value :=
      TKamScriptFloat(AResult).Value + TKamScriptFloat(Arguments[I]).Value;
end;

class procedure TKamScriptFloat.HandleSubtract(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  I: Integer;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := TKamScriptFloat(Arguments[0]).Value;
  for I := 1 to Length(Arguments) - 1 do
    TKamScriptFloat(AResult).Value :=
      TKamScriptFloat(AResult).Value - TKamScriptFloat(Arguments[I]).Value;
end;

class procedure TKamScriptFloat.HandleMultiply(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  I: Integer;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := TKamScriptFloat(Arguments[0]).Value;
  for I := 1 to Length(Arguments) - 1 do
    TKamScriptFloat(AResult).Value :=
      TKamScriptFloat(AResult).Value * TKamScriptFloat(Arguments[I]).Value;
end;

class procedure TKamScriptFloat.HandleDivide(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  I: Integer;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := TKamScriptFloat(Arguments[0]).Value;
  for I := 1 to Length(Arguments) - 1 do
    TKamScriptFloat(AResult).Value :=
      TKamScriptFloat(AResult).Value / TKamScriptFloat(Arguments[I]).Value;
end;

class procedure TKamScriptFloat.HandleNegate(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := - TKamScriptFloat(Arguments[0]).Value;
end;

class procedure TKamScriptFloat.HandleModulo(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value :=
    TKamScriptFloat(Arguments[0]).Value -
    Floor( TKamScriptFloat(Arguments[0]).Value /
           TKamScriptFloat(Arguments[1]).Value )
    * TKamScriptFloat(Arguments[1]).Value;
end;

class procedure TKamScriptFloat.HandleSin(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Sin( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleCos(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Cos( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleTan(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Tan( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleCotan(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := KamCoTan( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleArcSin(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := ArcSin( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleArcCos(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := ArcCos( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleArcTan(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := ArcTan( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleArcCotan(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := ArcCot( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleSinh(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := SinH( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleCosh(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := CosH( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleTanh(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := TanH( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleCotanh(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := 1 / TanH( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleLog2(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Log2( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleLn(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Ln( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleLog(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Logn( TKamScriptFloat(Arguments[0]).Value,
                                          TKamScriptFloat(Arguments[1]).Value );
end;

class procedure TKamScriptFloat.HandlePower2(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Power(2, TKamScriptFloat(Arguments[0]).Value);
end;

class procedure TKamScriptFloat.HandleExp(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Exp( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandlePower(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := GeneralPower(
    TKamScriptFloat(Arguments[0]).Value,
    TKamScriptFloat(Arguments[1]).Value );
end;

class procedure TKamScriptFloat.HandleSqr(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Sqr( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleSqrt(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Sqrt( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleSgn(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := Sign( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleAbs(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := Abs( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleCeil(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := Ceil( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleFloor(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptInteger);
  TKamScriptInteger(AResult).Value := Floor( TKamScriptFloat(Arguments[0]).Value );
end;

class procedure TKamScriptFloat.HandleGreater(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptFloat(Arguments[0]).Value >
    TKamScriptFloat(Arguments[1]).Value;
end;

class procedure TKamScriptFloat.HandleLesser(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptFloat(Arguments[0]).Value <
    TKamScriptFloat(Arguments[1]).Value;
end;

class procedure TKamScriptFloat.HandleGreaterEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptFloat(Arguments[0]).Value >=
    TKamScriptFloat(Arguments[1]).Value;
end;

class procedure TKamScriptFloat.HandleLesserEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptFloat(Arguments[0]).Value <=
    TKamScriptFloat(Arguments[1]).Value;
end;

class procedure TKamScriptFloat.HandleEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptFloat(Arguments[0]).Value =
    TKamScriptFloat(Arguments[1]).Value;
end;

class procedure TKamScriptFloat.HandleNotEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptFloat(Arguments[0]).Value <>
    TKamScriptFloat(Arguments[1]).Value;
end;

class procedure TKamScriptFloat.ConvertFromInt(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := TKamScriptInteger(Arguments[0]).Value;
end;

class procedure TKamScriptFloat.ConvertFromFloat(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  if ParentOfResult then
    AResult.FreeByParentExpression else
    AResult := nil;

  AResult := Arguments[0];
  Assert(AResult is TKamScriptFloat);
  ParentOfResult := false;
end;

class procedure TKamScriptFloat.ConvertFromBool(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  BoolTo01: array [boolean] of Float = (0, 1);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  TKamScriptFloat(AResult).Value := BoolTo01[TKamScriptBoolean(Arguments[0]).Value];
end;

class procedure TKamScriptFloat.ConvertFromString(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptFloat);
  try
    TKamScriptFloat(AResult).Value := StrToFloat(TKamScriptString(Arguments[0]).Value);
  except
    on E: EConvertError do
      { Change EConvertError to EKamScriptError }
      raise EKamScriptError.CreateFmt('Error when converting string "%s" to float: %s',
        [TKamScriptString(Arguments[0]).Value, E.Message]);
  end;
end;

procedure TKamScriptFloat.AssignValue(Source: TKamScriptValue);
begin
  if Source is TKamScriptFloat then
    Value := TKamScriptFloat(Source).Value else
  { This allows for type promotion integer->float at assignment. }
  if Source is TKamScriptInteger then
    Value := TKamScriptInteger(Source).Value else
    raise EKamAssignValueError.CreateFmt('Assignment from %s to %s not possible', [Source.ClassName, ClassName]);
end;

procedure TKamScriptFloat.SetValue(const AValue: Float);
begin
  FValue := AValue;
  ValueAssigned := true;
end;

{ TKamScriptBoolean ---------------------------------------------------------- }

constructor TKamScriptBoolean.Create(AValue: boolean);
begin
  Create;
  Value := AValue;
end;

constructor TKamScriptBoolean.Create;
begin
  inherited Create;
end;

class procedure TKamScriptBoolean.HandleOr(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptBoolean(Arguments[0]).Value or
    TKamScriptBoolean(Arguments[1]).Value;
end;

class procedure TKamScriptBoolean.HandleAnd(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptBoolean(Arguments[0]).Value and
    TKamScriptBoolean(Arguments[1]).Value;
end;

class procedure TKamScriptBoolean.HandleNot(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    not TKamScriptBoolean(Arguments[0]).Value;
end;

class procedure TKamScriptBoolean.HandleGreater(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptBoolean(Arguments[0]).Value >
    TKamScriptBoolean(Arguments[1]).Value;
end;

class procedure TKamScriptBoolean.HandleLesser(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptBoolean(Arguments[0]).Value <
    TKamScriptBoolean(Arguments[1]).Value;
end;

class procedure TKamScriptBoolean.HandleGreaterEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptBoolean(Arguments[0]).Value >=
    TKamScriptBoolean(Arguments[1]).Value;
end;

class procedure TKamScriptBoolean.HandleLesserEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptBoolean(Arguments[0]).Value <=
    TKamScriptBoolean(Arguments[1]).Value;
end;

class procedure TKamScriptBoolean.HandleEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptBoolean(Arguments[0]).Value =
    TKamScriptBoolean(Arguments[1]).Value;
end;

class procedure TKamScriptBoolean.HandleNotEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptBoolean(Arguments[0]).Value <>
    TKamScriptBoolean(Arguments[1]).Value;
end;

class procedure TKamScriptBoolean.ConvertFromInt(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value := TKamScriptInteger(Arguments[0]).Value <> 0;
end;

class procedure TKamScriptBoolean.ConvertFromFloat(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value := TKamScriptFloat(Arguments[0]).Value <> 0;
end;

class procedure TKamScriptBoolean.ConvertFromBool(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  if ParentOfResult then
    AResult.FreeByParentExpression else
    AResult := nil;

  AResult := Arguments[0];
  Assert(AResult is TKamScriptBoolean);
  ParentOfResult := false;
end;

class procedure TKamScriptBoolean.ConvertFromString(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  S: string;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  S := LowerCase(TKamScriptString(Arguments[0]).Value);
  if S = 'false' then
    TKamScriptBoolean(AResult).Value := false else
  if S = 'true' then
    TKamScriptBoolean(AResult).Value := true else
    raise EKamScriptError.CreateFmt('Error when converting string "%s" to boolean: invalid value, must be "false" or "true"',
      [TKamScriptString(Arguments[0]).Value]);
end;

procedure TKamScriptBoolean.AssignValue(Source: TKamScriptValue);
begin
  if Source is TKamScriptBoolean then
    Value := TKamScriptBoolean(Source).Value else
    raise EKamAssignValueError.CreateFmt('Assignment from %s to %s not possible', [Source.ClassName, ClassName]);
end;

procedure TKamScriptBoolean.SetValue(const AValue: Boolean);
begin
  FValue := AValue;
  ValueAssigned := true;
end;

{ TKamScriptString ---------------------------------------------------------- }

constructor TKamScriptString.Create(AValue: string);
begin
  Create;
  Value := AValue;
end;

constructor TKamScriptString.Create;
begin
  inherited Create;
end;

class procedure TKamScriptString.HandleAdd(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  I: Integer;
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptString);
  { The function allows only >= 1 arguments, and this handler is
    registered only for TKamScriptString values, so we can safely take
    the first arg as TKamScriptString. }
  TKamScriptString(AResult).Value := TKamScriptString(Arguments[0]).Value;
  for I := 1 to Length(Arguments) - 1 do
    TKamScriptString(AResult).Value :=
      TKamScriptString(AResult).Value + TKamScriptString(Arguments[I]).Value;
end;

class procedure TKamScriptString.HandleGreater(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptString(Arguments[0]).Value >
    TKamScriptString(Arguments[1]).Value;
end;

class procedure TKamScriptString.HandleLesser(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptString(Arguments[0]).Value <
    TKamScriptString(Arguments[1]).Value;
end;

class procedure TKamScriptString.HandleGreaterEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptString(Arguments[0]).Value >=
    TKamScriptString(Arguments[1]).Value;
end;

class procedure TKamScriptString.HandleLesserEq(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptString(Arguments[0]).Value <=
    TKamScriptString(Arguments[1]).Value;
end;

class procedure TKamScriptString.HandleEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptString(Arguments[0]).Value =
    TKamScriptString(Arguments[1]).Value;
end;

class procedure TKamScriptString.HandleNotEqual(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptBoolean);
  TKamScriptBoolean(AResult).Value :=
    TKamScriptString(Arguments[0]).Value <>
    TKamScriptString(Arguments[1]).Value;
end;

class procedure TKamScriptString.ConvertFromInt(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptString);
  TKamScriptString(AResult).Value := IntToStr(TKamScriptInteger(Arguments[0]).Value);
end;

class procedure TKamScriptString.ConvertFromFloat(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptString);
  TKamScriptString(AResult).Value := FloatToStr(TKamScriptFloat(Arguments[0]).Value);
end;

class procedure TKamScriptString.ConvertFromBool(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
var
  BoolTo01: array [boolean] of string = ('false', 'true');
begin
  CreateValueIfNeeded(AResult, ParentOfResult, TKamScriptString);
  TKamScriptString(AResult).Value := BoolTo01[TKamScriptBoolean(Arguments[0]).Value];
end;

class procedure TKamScriptString.ConvertFromString(const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  if ParentOfResult then
    AResult.FreeByParentExpression else
    AResult := nil;

  AResult := Arguments[0];
  Assert(AResult is TKamScriptString);
  ParentOfResult := false;
end;

procedure TKamScriptString.AssignValue(Source: TKamScriptValue);
begin
  if Source is TKamScriptString then
    Value := TKamScriptString(Source).Value else
    raise EKamAssignValueError.CreateFmt('Assignment from %s to %s not possible', [Source.ClassName, ClassName]);
end;

procedure TKamScriptString.SetValue(const AValue: String);
begin
  FValue := AValue;
  ValueAssigned := true;
end;

{ TKamScriptFunction --------------------------------------------------------- }

constructor TKamScriptFunction.Create(AArgs: TKamScriptExpressionsList);
begin
  inherited Create;
  FArgs := TKamScriptExpressionsList.CreateFromList(AArgs);
  CheckArguments;
end;

constructor TKamScriptFunction.Create(const AArgs: array of TKamScriptExpression);
begin
  inherited Create;
  FArgs := TKamScriptExpressionsList.CreateFromArray(AArgs);
  CheckArguments;
end;

procedure TKamScriptFunction.CheckArguments;
begin
end;

destructor TKamScriptFunction.Destroy;
begin
  if FArgs <> nil then
  begin
    FArgs.FreeContentsByParentExpression;
    FreeAndNil(FArgs);
  end;

  if ParentOfLastExecuteResult then
    LastExecuteResult.FreeByParentExpression;
  LastExecuteResult := nil;

  inherited;
end;

class function TKamScriptFunction.InfixOperatorName: string;
begin
  Result := '';
end;

function TKamScriptFunction.Execute: TKamScriptValue;

  function ArgumentClassesToStr(const A: TKamScriptValueClassArray): string;
  var
    I: Integer;
  begin
    Result := '';
    for I := 0 to Length(A) - 1 do
    begin
      if I > 0 then Result += ', ';
      Result += A[I].ClassName;
    end;
    Result := '(' + Result + ')';
  end;

var
  HandlersByArgument: TObjectList;
  Handler: TKamScriptRegisteredHandler;
  Arguments: array of TKamScriptValue;
  ArgumentClasses: TKamScriptValueClassArray;
  I: Integer;
begin
  if FunctionHandlers.SearchFunctionClass(
    TKamScriptFunctionClass(Self.ClassType), HandlersByArgument) then
  begin
    { We have to calculate arguments first, to know their type,
      to decide which handler is suitable. }
    SetLength(Arguments, Args.Count);
    SetLength(ArgumentClasses, Args.Count);
    for I := 0 to Args.Count - 1 do
    begin
      Arguments[I] := Args[I].Execute;
      ArgumentClasses[I] := TKamScriptValueClass(Arguments[I].ClassType);
    end;

    { calculate Handler }
    if not FunctionHandlers.SearchArgumentClasses(
      HandlersByArgument, ArgumentClasses, Handler) then
    begin
      { try promoting integer arguments to float, see if it will work then }
      for I := 0 to Length(ArgumentClasses) - 1 do
        if ArgumentClasses[I].InheritsFrom(TKamScriptInteger) then
          ArgumentClasses[I] := TKamScriptFloat;

      if FunctionHandlers.SearchArgumentClasses(
        HandlersByArgument, ArgumentClasses, Handler) then
      begin
        { So I found a handler, that will be valid if all integer args will
          get promoted to float. Cool, let's do it.

          I use PromoteToFloat method, that will keep it's result valid
          for some time, since (depending on function handler) we may
          return PromoteToFloat result to the user. }
        for I := 0 to Length(Arguments) - 1 do
          if Arguments[I] is TKamScriptInteger then
            Arguments[I] := TKamScriptInteger(Arguments[I]).PromoteToFloat;
      end else
        raise EKamScriptFunctionNoHandler.CreateFmt('Function "%s" is not defined for this combination of arguments: %s',
          [Name, ArgumentClassesToStr(ArgumentClasses)]);
    end;

    Handler.Handler(Arguments, LastExecuteResult, ParentOfLastExecuteResult);

    { Force raising pending exceptions by FP calculations in Handler.Handler. }
    ClearExceptions(true);

    Result := LastExecuteResult;
  end else
    raise EKamScriptFunctionNoHandler.CreateFmt('No handler defined for function "%s"', [Name]);
end;

{ TKamScriptRegisteredHandler ------------------------------------------------ }

constructor TKamScriptRegisteredHandler.Create(
  AHandler: TKamScriptFunctionHandler;
  AFunctionClass: TKamScriptFunctionClass;
  const AArgumentClasses: TKamScriptValueClassArray;
  const AVariableArgumentsCount: boolean);
begin
  FHandler := AHandler;
  FFunctionClass := AFunctionClass;
  FArgumentClasses := AArgumentClasses;
  FVariableArgumentsCount := AVariableArgumentsCount;
end;

{ TKamScriptSequence --------------------------------------------------------- }

class function TKamScriptSequence.Name: string;
begin
  Result := 'sequence (;)';
end;

class function TKamScriptSequence.ShortName: string;
begin
  Result := '';
end;

class function TKamScriptSequence.InfixOperatorName: string;
begin
  Result := ';';
end;

class procedure TKamScriptSequence.HandleSequence(
  const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  if ParentOfResult then
    AResult.FreeByParentExpression else
    AResult := nil;

  AResult := Arguments[High(Arguments)];
  ParentOfResult := false;
end;

{ TKamScriptAssignment --------------------------------------------------------- }

class function TKamScriptAssignment.Name: string;
begin
  Result := 'assignment (:=)';
end;

class function TKamScriptAssignment.ShortName: string;
begin
  Result := '';
end;

class function TKamScriptAssignment.InfixOperatorName: string;
begin
  Result := ':=';
end;

class procedure TKamScriptAssignment.HandleAssignment(
  const Arguments: array of TKamScriptValue; var AResult: TKamScriptValue; var ParentOfResult: boolean);
begin
  if ParentOfResult then
    AResult.FreeByParentExpression else
    AResult := nil;

  (Arguments[0] as TKamScriptValue).AssignValue(Arguments[1]);

  AResult := Arguments[0] as TKamScriptValue;
  ParentOfResult := false;
end;

procedure TKamScriptAssignment.CheckArguments;
begin
  inherited;
  if not ( (Args[0] is TKamScriptValue) and
           (TKamScriptValue(Args[0]).Name <> '') ) then
    raise EKamScriptFunctionArgumentsError.Create('Left side of assignment expression is not a writeable operand');
end;

{ TKamScriptFunctionHandlers ------------------------------------------------- }

constructor TKamScriptFunctionHandlers.Create;
begin
  inherited;
  FHandlersByFunction := TObjectList.Create(true);
end;

destructor TKamScriptFunctionHandlers.Destroy;
begin
  FreeAndNil(FHandlersByFunction);
  inherited;
end;

function TKamScriptFunctionHandlers.SearchFunctionClass(
  FunctionClass: TKamScriptFunctionClass;
  out FunctionIndex: Integer;
  out HandlersByArgument: TObjectList): boolean;
var
  I: Integer;
begin
  for I := 0 to FHandlersByFunction.Count - 1 do
  begin
    HandlersByArgument := FHandlersByFunction[I] as TObjectList;
    if FunctionClass = (HandlersByArgument[0] as
      TKamScriptRegisteredHandler).FunctionClass then
    begin
      FunctionIndex := I;
      Result := true;
      Exit;
    end;
  end;
  Result := false;
end;

function TKamScriptFunctionHandlers.SearchFunctionClass(
  FunctionClass: TKamScriptFunctionClass;
  out HandlersByArgument: TObjectList): boolean;
var
  FunctionIndex: Integer;
begin
  Result := SearchFunctionClass(
    FunctionClass, FunctionIndex, HandlersByArgument);
end;

function TKamScriptFunctionHandlers.SearchArgumentClasses(
  HandlersByArgument: TObjectList;
  const ArgumentClasses: TKamScriptValueClassArray;
  out ArgumentIndex: Integer;
  out Handler: TKamScriptRegisteredHandler): boolean;
var
  I, J: Integer;
begin
  for I := 0 to HandlersByArgument.Count - 1 do
  begin
    Handler := HandlersByArgument[I] as TKamScriptRegisteredHandler;
    Result := true;
    for J := 0 to Length(ArgumentClasses) - 1 do
    begin
      Assert(Result);

      if J < Length(Handler.ArgumentClasses) then
        Result := ArgumentClasses[J].InheritsFrom(Handler.ArgumentClasses[J]) else
        { This is more than required number of arguments.
          Still it's Ok if it matches last argument and function allows variable
          number of arguments. }
        Result := Handler.VariableArgumentsCount and
          (Length(Handler.ArgumentClasses) > 0) and
          ArgumentClasses[J].InheritsFrom(
            Handler.ArgumentClasses[High(Handler.ArgumentClasses)]);

      if not Result then Break;
    end;

    if Result then
    begin
      ArgumentIndex := I;
      Exit;
    end
  end;
  Result := false;
end;

function TKamScriptFunctionHandlers.SearchArgumentClasses(
  HandlersByArgument: TObjectList;
  const ArgumentClasses: TKamScriptValueClassArray;
  out Handler: TKamScriptRegisteredHandler): boolean;
var
  ArgumentIndex: Integer;
begin
  Result := SearchArgumentClasses(
    HandlersByArgument, ArgumentClasses, ArgumentIndex, Handler);
end;

procedure TKamScriptFunctionHandlers.RegisterHandler(
  AHandler: TKamScriptFunctionHandler;
  AFunctionClass: TKamScriptFunctionClass;
  const AArgumentClasses: array of TKamScriptValueClass;
  const AVariableArgumentsCount: boolean);
var
  HandlersByArgument: TObjectList;
  Handler: TKamScriptRegisteredHandler;
  ArgumentClassesDyn: TKamScriptValueClassArray;
begin
  SetLength(ArgumentClassesDyn, High(AArgumentClasses) + 1);
  if Length(ArgumentClassesDyn) > 0 then
    Move(AArgumentClasses[0], ArgumentClassesDyn[0],
      SizeOf(TKamScriptValueClass) * Length(ArgumentClassesDyn));

  if SearchFunctionClass(AFunctionClass, HandlersByArgument) then
  begin
    if not SearchArgumentClasses(HandlersByArgument, ArgumentClassesDyn, Handler) then
    begin
      Handler := TKamScriptRegisteredHandler.Create(
        AHandler, AFunctionClass, ArgumentClassesDyn, AVariableArgumentsCount);
      HandlersByArgument.Add(Handler);
    end;
  end else
  begin
    HandlersByArgument := TObjectList.Create(true);
    FHandlersByFunction.Add(HandlersByArgument);

    Handler := TKamScriptRegisteredHandler.Create(
      AHandler, AFunctionClass, ArgumentClassesDyn, AVariableArgumentsCount);
    HandlersByArgument.Add(Handler);
  end;
end;

function TKamScriptFunctionHandlers.SearchFunctionShortName(
  const AShortName: string): TKamScriptFunctionClass;
var
  I: Integer;
  HandlersByArgument: TObjectList;
begin
  for I := 0 to FHandlersByFunction.Count - 1 do
  begin
    HandlersByArgument := FHandlersByFunction[I] as TObjectList;
    Result := (HandlersByArgument[0] as
      TKamScriptRegisteredHandler).FunctionClass;
    if SameText(AShortName, Result.ShortName) then
      Exit;
  end;
  Result := nil;
end;

{ TKamScriptFunctionDefinition ----------------------------------------------- }

constructor TKamScriptFunctionDefinition.Create;
begin
  inherited;
  FParameters := TKamScriptValuesList.Create;
end;

destructor TKamScriptFunctionDefinition.Destroy;
begin
  if Body <> nil then
    Body.FreeByParentExpression;
  FreeWithContentsAndNil(FParameters);
  inherited;
end;

{ TKamScriptFunctionDefinitionsList ------------------------------------------ }

function TKamScriptFunctionDefinitionsList.IndexOf(
  const FunctionName: string): Integer;
begin
  for Result := 0 to Count - 1 do
    if SameText(FunctionName, Items[Result].Name) then
      Exit;
  Result := -1;
end;

{ TKamScriptProgram ---------------------------------------------------------- }

constructor TKamScriptProgram.Create;
begin
  inherited;
  FFunctions := TKamScriptFunctionDefinitionsList.Create;
end;

destructor TKamScriptProgram.Destroy;
begin
  FreeWithContentsAndNil(FFunctions);
  inherited;
end;

procedure TKamScriptProgram.ExecuteFunction(const FunctionName: string;
  const Parameters: array of Float;
  const IgnoreMissingFunction: boolean);
var
  Func: TKamScriptFunctionDefinition;
  FuncIndex, I: Integer;
begin
  FuncIndex := Functions.IndexOf(FunctionName);
  if FuncIndex = -1 then
  begin
    if IgnoreMissingFunction then
      Exit else
      raise EKamScriptMissingFunction.CreateFmt('KambiScript function "%s" is not defined', [FunctionName]);
  end;
  Func := Functions[FuncIndex];

  if High(Parameters) <> Func.Parameters.High then
    raise EKamScriptError.CreateFmt('KambiScript function "%s" requires %d parameters, but passed %d parameters',
      [FunctionName, Func.Parameters.Count, High(Parameters) + 1]);

  { TODO: this is directed at only TKamScriptFloat now, so
    Parameters are Float and below we just cast to TKamScriptFloat. }

  for I := 0 to High(Parameters) do
    (Func.Parameters[I] as TKamScriptFloat).Value := Parameters[I];

  Func.Body.Execute;
end;

{ procedural utils ----------------------------------------------------------- }

procedure CreateValueIfNeeded(var Value: TKamScriptValue;
  var ParentOfValue: boolean;
  NeededClass: TKamScriptValueClass);
begin
  if Value = nil then
  begin
    Value := NeededClass.Create;
    ParentOfValue := true;
  end else
  if Value.ClassType <> NeededClass then
  begin
    if ParentOfValue then
      Value.FreeByParentExpression else
      Value := nil;

    Value := NeededClass.Create;
    ParentOfValue := true;
  end;
end;

{ unit init/fini ------------------------------------------------------------- }

initialization
  {$ifdef WORKAROUND_EXCEPTIONS_FOR_SCRIPT_EXPRESSIONS}
  Set8087CW($133F);
  {$endif}

  FunctionHandlers := TKamScriptFunctionHandlers.Create;

  FunctionHandlers.RegisterHandler(@TKamScriptSequence(nil).HandleSequence, TKamScriptSequence, [TKamScriptValue], true);
  FunctionHandlers.RegisterHandler(@TKamScriptAssignment(nil).HandleAssignment, TKamScriptAssignment, [TKamScriptValue, TKamScriptValue], false);

  { Register handlers for TKamScriptInteger for functions in
    KambiScriptMathFunctions. }
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleAdd, TKamScriptAdd, [TKamScriptInteger], true);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleSubtract, TKamScriptSubtract, [TKamScriptInteger], true);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleNegate, TKamScriptNegate, [TKamScriptInteger], false);

  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleMultiply, TKamScriptMultiply, [TKamScriptInteger], true);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleDivide, TKamScriptDivide, [TKamScriptInteger], true);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleModulo, TKamScriptModulo, [TKamScriptInteger, TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandlePower, TKamScriptPower, [TKamScriptInteger, TKamScriptInteger], false);

  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleSqr, TKamScriptSqr, [TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleSgn, TKamScriptSgn, [TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleAbs, TKamScriptAbs, [TKamScriptInteger], false);

  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleGreater, TKamScriptGreater, [TKamScriptInteger, TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleLesser, TKamScriptLesser, [TKamScriptInteger, TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleGreaterEq, TKamScriptGreaterEq, [TKamScriptInteger, TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleLesserEq, TKamScriptLesserEq, [TKamScriptInteger, TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleEqual, TKamScriptEqual, [TKamScriptInteger, TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).HandleNotEqual, TKamScriptNotEqual, [TKamScriptInteger, TKamScriptInteger], false);

  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).ConvertFromInt   , TKamScriptInt, [TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).ConvertFromFloat , TKamScriptInt, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).ConvertFromBool  , TKamScriptInt, [TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptInteger(nil).ConvertFromString, TKamScriptInt, [TKamScriptString], false);

  { Register handlers for TKamScriptFloat for functions in
    KambiScriptMathFunctions. }
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleAdd, TKamScriptAdd, [TKamScriptFloat], true);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleSubtract, TKamScriptSubtract, [TKamScriptFloat], true);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleMultiply, TKamScriptMultiply, [TKamScriptFloat], true);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleDivide, TKamScriptDivide, [TKamScriptFloat], true);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleNegate, TKamScriptNegate, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleModulo, TKamScriptModulo, [TKamScriptFloat, TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleSin, TKamScriptSin, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleCos, TKamScriptCos, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleTan, TKamScriptTan, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleCotan, TKamScriptCotan, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleArcSin, TKamScriptArcSin, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleArcCos, TKamScriptArcCos, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleArcTan, TKamScriptArcTan, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleArcCotan, TKamScriptArcCotan, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleSinh, TKamScriptSinh, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleCosh, TKamScriptCosh, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleTanh, TKamScriptTanh, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleCotanh, TKamScriptCotanh, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleLog2, TKamScriptLog2, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleLn, TKamScriptLn, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleLog, TKamScriptLog, [TKamScriptFloat, TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandlePower2, TKamScriptPower2, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleExp, TKamScriptExp, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandlePower, TKamScriptPower, [TKamScriptFloat, TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleSqr, TKamScriptSqr, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleSqrt, TKamScriptSqrt, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleSgn, TKamScriptSgn, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleAbs, TKamScriptAbs, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleCeil, TKamScriptCeil, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleFloor, TKamScriptFloor, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleGreater, TKamScriptGreater, [TKamScriptFloat, TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleLesser, TKamScriptLesser, [TKamScriptFloat, TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleGreaterEq, TKamScriptGreaterEq, [TKamScriptFloat, TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleLesserEq, TKamScriptLesserEq, [TKamScriptFloat, TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleEqual, TKamScriptEqual, [TKamScriptFloat, TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).HandleNotEqual, TKamScriptNotEqual, [TKamScriptFloat, TKamScriptFloat], false);

  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).ConvertFromInt   , TKamScriptFloatFun, [TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).ConvertFromFloat , TKamScriptFloatFun, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).ConvertFromBool  , TKamScriptFloatFun, [TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptFloat(nil).ConvertFromString, TKamScriptFloatFun, [TKamScriptString], false);

  { Register handlers for TKamScriptBoolean for functions in
    KambiScriptMathFunctions. }
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).HandleOr, TKamScriptOr, [TKamScriptBoolean, TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).HandleAnd, TKamScriptAnd, [TKamScriptBoolean, TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).HandleNot, TKamScriptNot, [TKamScriptBoolean], false);

  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).HandleGreater, TKamScriptGreater, [TKamScriptBoolean, TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).HandleLesser, TKamScriptLesser, [TKamScriptBoolean, TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).HandleGreaterEq, TKamScriptGreaterEq, [TKamScriptBoolean, TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).HandleLesserEq, TKamScriptLesserEq, [TKamScriptBoolean, TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).HandleEqual, TKamScriptEqual, [TKamScriptBoolean, TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).HandleNotEqual, TKamScriptNotEqual, [TKamScriptBoolean, TKamScriptBoolean], false);

  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).ConvertFromInt   , TKamScriptBool, [TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).ConvertFromFloat , TKamScriptBool, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).ConvertFromBool  , TKamScriptBool, [TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptBoolean(nil).ConvertFromString, TKamScriptBool, [TKamScriptString], false);

  { Register handlers for TKamScriptString for functions in
    KambiScriptMathFunctions. }
  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).HandleAdd, TKamScriptAdd, [TKamScriptString, TKamScriptString], false);

  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).HandleGreater, TKamScriptGreater, [TKamScriptString, TKamScriptString], false);
  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).HandleLesser, TKamScriptLesser, [TKamScriptString, TKamScriptString], false);
  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).HandleGreaterEq, TKamScriptGreaterEq, [TKamScriptString, TKamScriptString], false);
  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).HandleLesserEq, TKamScriptLesserEq, [TKamScriptString, TKamScriptString], false);
  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).HandleEqual, TKamScriptEqual, [TKamScriptString, TKamScriptString], false);
  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).HandleNotEqual, TKamScriptNotEqual, [TKamScriptString, TKamScriptString], false);

  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).ConvertFromInt   , TKamScriptStringFun, [TKamScriptInteger], false);
  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).ConvertFromFloat , TKamScriptStringFun, [TKamScriptFloat], false);
  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).ConvertFromBool  , TKamScriptStringFun, [TKamScriptBoolean], false);
  FunctionHandlers.RegisterHandler(@TKamScriptString(nil).ConvertFromString, TKamScriptStringFun, [TKamScriptString], false);
finalization
  FreeAndNil(FunctionHandlers);
end.
