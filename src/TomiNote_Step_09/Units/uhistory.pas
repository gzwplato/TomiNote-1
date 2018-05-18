unit uHistory;

{$mode objfpc}{$H+}

// String constants and string literals require this option
// 字符串常量和字符串字面量需要此选项
{$codepage UTF8}

interface

uses
  Classes, SysUtils, StdCtrls, Forms, Clipbrd;

type

  PStep = ^TStep;

  // One step of history data | 单步历史记录数据
  TStep = record
    // < 0 means Delete text, > 0 means Insert text
    // < 0 表示删除文本，> 0 表示添加文本
    SelStart              : SizeInt;
    // Inserted or Deleteed text
    // 添加或删除的文本内容
    SelText               : string;
    // 0 means full one step, 1 means first half step, 2 means second half step.
    // 0 表示完整一步，1 表示前半步，2 表示后半步
    HalfStep              : Integer;
  end;

  { TSteps }

  PSteps = ^TSteps;

  // The history data must be stored separately and cannot be mixed with THistory.
  // Because history data needs to be switched at any time.
  // 历史记录数据必须单独存放，不能和 THistory 混在一起，因为历史记录数据需要随时切换
  TSteps = class(TList)
  private
    FIndex                   : Integer; // History index, based 0 | 历史记录索引，从 0 开始
    FSize                    : SizeInt; // All steps size | 所有历史步骤的总大小

    procedure AddStep(ASelStart: SizeInt; ASelText: string; AHalfEvent: Boolean);
    procedure DelStep(AIndex: Integer);

    function  GetStep(AIndex: Integer): PStep; inline;
    function  CurStep: PStep; inline;
  public
    constructor Create;
    destructor  Destroy; override;

    property  Size: SizeInt read FSize;
  end;

  { THistory }

  THistory = class
  private
    FMemo                    : TMemo;
    FOldOnChange             : TNotifyEvent;
    // The content of FMemo before OnChange event
    // OnChange 事件之前的 FMemo 内容
    FPrevContent             : string;

    // History records data | 历史记录数据
    FSteps                   : TSteps;

    FInEdit                  : Boolean;
    FixOnChangeBug           : Boolean;

    FOldApplicationIdle      : TIdleEvent;
    // Whether this OnChange event is a half event triggered by one v"user operation".
    // 这个 OnChange 事件是否是单个“用户操作”所触发的半个事件。
    FHalfEvent               : Boolean;
    FPrevSelStart            : SizeInt;

    procedure MemoOnChange(Sender: TObject);
    procedure ApplicationIdle(Sender: TObject; var Done: Boolean);

    function  StrDiff(const ACurContent: string; out ASelStart: SizeInt;
      out ASelText: string; out AHalfEvent: Boolean): Boolean;

    function  StrDiff1(const ACurContent: string; out ASelStart: SizeInt;
      out ASelText: string; out AHalfEvent: Boolean): Boolean;

    function  StrDiff2(const ACurContent: string; out ASelStart: SizeInt;
      out ASelText: string; out AHalfEvent: Boolean): Boolean;

  public
    constructor Create(AMemo: TMemo);
    destructor  Destroy; override;

    function  CanUndo: Boolean; inline;
    function  CanRedo: Boolean; inline;
    procedure Undo;
    procedure Redo;

    // You should use PasteText function to paste text instead of FMemo.PasteFromClipboard function.
    // This function can reduce the calculation.
    // 你应该使用 PasteText 函数粘贴文本，而不是 FMemo.PasteFromClipboard 函数，
    // 此函数可以减少计算量。
    procedure PasteText;

    // You should use the DeleteText function to delete text instead of the FMemo.Text := '' method,
    // otherwise your delete operation may not trigger the OnChange event.
    // 你应该使用 DeleteText 函数删除文本，而不是 FMemo.Text := '' 方法，
    // 否则你的删除操作可能不会触发 OnChange 事件。
    procedure DeleteText;

    procedure Reset; inline;

    function  GetHistoryData: TSteps;
    procedure SetHistoryData(Data: TSteps; const NewContent: string);

    // FMemo.Text consumes a lot of CPU resources when reading large text. To improve efficiency,
    // don't use FMemo.Text frequently. In this unit, FPrevContent are synchronized with FMemo.Text,
    // it can be used by external code at any time. In this unit, basically using FPrevContent
    // instead of FMemo.Text.
    // FMemo.Text 在读取大文本时会消耗许多 CPU 资源。为了提高效率，不要经常使用 FMemo.Text，在本单元中，
    // FPrevContent 的内容和 FMemo.Text 的内容是同步的，可以随时被外部代码调用，在本单元内部，基本上
    // 也是使用 FPrevContent 代替 FMemo.Text。
    property  MemoContent: string read FPrevContent;
    property  Size: SizeInt read FSteps.FSize;
    property  InEdit: Boolean read FInEdit write FInEdit;
  end;

  { Custom Functions }

  function UTF8PosToBytePos(const Text: PChar; const Size: SizeInt; UPos: SizeInt): SizeInt;
  function UTF8PosToBytePos(const Text: String; const UPos: SizeInt): SizeInt; inline;
  function UTF8LengthFast(const Text: PChar; const Size: SizeInt): SizeInt;
  function UTF8LengthFast(const AStr: String): SizeInt; inline;

implementation

{ TSteps }

constructor TSteps.Create;
begin
  inherited Create;
  FIndex := -1;
end;

destructor TSteps.Destroy;
begin
  DelStep(0);
  inherited Destroy;
end;

function TSteps.GetStep(AIndex: Integer): PStep; inline;
begin
  Result := PStep(Items[AIndex]);
end;

function TSteps.CurStep: PStep; inline;
begin
  Result := PStep(Items[FIndex]);
end;

procedure TSteps.AddStep(ASelStart: SizeInt; ASelText: string; AHalfEvent: Boolean);
begin
  // Remove the following steps | 移除后续的历史步骤
  DelStep(FIndex + 1);

  // Correct the previous step | 修正前一步历史记录
  if AHalfEvent and (FIndex >= 0) then
    GetStep(FIndex)^.HalfStep := 1;  // First half step | 前半步

  // Add current step | 添加当前历史步骤
  Add(new(PStep));
  Inc(FIndex);
  Inc(FSize, Sizeof(TStep) + Length(ASelText));

  with CurStep^ do begin
    SelStart := ASelStart;
    SelText  := ASelText;
    if AHalfEvent then
      HalfStep := 2   // Second half step | 后半步
    else
      HalfStep := 0;  // Full one step | 完整一步
    // writeln(Format('AddStep: %d, %s, %d', [SelStart, SelText, HalfStep]));
  end;
end;

procedure TSteps.DelStep(AIndex: Integer);
var
  i: Integer;
  Step: PStep;
begin
  for i := Count - 1 downto AIndex do begin
    Step := GetStep(i);
    // Size | 大小
    Dec(FSize, Sizeof(TStep) + Length(Step^.SelText));
    // Memory | 内存
    Step^.SelText := '';
    dispose(Step);
    // List | 列表
    Delete(i);
  end;
  // Index | 索引
  FIndex := AIndex - 1;
end;

{ THistory }

constructor THistory.Create(AMemo: TMemo);
begin
  inherited Create;
  // The history data of THistory should be managed and destroyed by itself,
  // even if it will be switched at any time.
  // THistory 的历史记录数据应该由自己管理和释放，即使它会随时被切换，也要保证这一点。
  FSteps := TSteps.Create;

  FMemo          := AMemo;
  FOldOnChange   := FMemo.OnChange;
  FMemo.OnChange := @MemoOnChange;

  FOldApplicationIdle := Application.OnIdle;
  Application.OnIdle  := @ApplicationIdle;

  FHalfEvent := False;

  // Do not initialize FPrevContent and FInEdit here, they should be Initialized
  // in SetHistoryData. You code shuold use THistory after execute SetHistoryData.
  // 不要在这里初始化 FPrevContent 和 FInEdit，它们应该在 SetHistoryData 中进行初始化。
  // 你的代码应该在执行了 SetHistoryData 之后才使用 THistory。
end;

destructor THistory.Destroy;
begin
  Application.OnIdle := FOldApplicationIdle;
  FMemo.OnChange     := FOldOnChange;
  FMemo              := nil;

  // The history data of THistory should be managed and destroyed by itself,
  // even if it will be switched at any time.
  // THistory 的历史记录数据应该由自己管理和释放，即使它会随时被切换，也要保证这一点。
  FSteps.Free;

  inherited Destroy;
end;

procedure THistory.MemoOnChange(Sender: TObject);
var
  CurContent, ASelText : string;
  ASelStart            : SizeInt;
  AHalfEvent           : Boolean;
begin
  if FInEdit then begin
    CurContent := FMemo.Text;
    if StrDiff(CurContent, ASelStart, ASelText, AHalfEvent) then
      FSteps.AddStep(ASelStart, ASelText, AHalfEvent);
    FPrevContent := CurContent;
  end;

  FixOnChangeBug := False;

  if Assigned(FOldOnChange) then
    FOldOnChange(Sender);
end;

procedure THistory.ApplicationIdle(Sender: TObject; var Done: Boolean);
begin
  FHalfEvent := False;
  FPrevSelStart := FMemo.SelStart;

  if Assigned(FOldApplicationIdle) then
    FOldApplicationIdle(Sender, Done);
end;

// Get the difference between ACurContent and FPrevContent.
// The difference can only be insert or delete text in one place, not allowed other difference.
// ASelStart  : The SelStart of the difference, based 1, > 0 means add text, < 0 means delete content.
// ASelText   : The content of the difference.
// AHalfEvent : Is it a half OnChange event of one User Operation.

// 获取 ACurContent 和 FPrevContent 之间的不同之处。
// 只能有一处增加或减少的内容，不允有许其他不同。
// ASelStart  : 不同之处的 SelStart，从 1 开始，> 0 表示添加文本，< 0 表示删除文本。
// ASelText   : 不同之处的文本内容
// AHalfEvent : 是否是单个“用户操作”所触发的半个 OnChange 事件。
function THistory.StrDiff(const ACurContent: string; out ASelStart: SizeInt;
  out ASelText: string; out AHalfEvent: Boolean): Boolean;
begin
  if FMemo.SelLength = 0 then begin
    Result := StrDiff1(ACurContent, ASelStart, ASelText, AHalfEvent);
  end else begin
    Result := StrDiff2(ACurContent, ASelStart, ASelText, AHalfEvent);
  end;
end;

// Get the difference between ACurContent and FPrevContent.
// The difference can only be insert or delete text in one place, not allowed other difference.
// ASelStart  : the SelStart of the difference, based 1, > 0 means add text, < 0 means delete content.
// ASelText   : the content of the difference.
// AHalfEvent : is it a half OnChange event of one User Operation.

// 获取 ACurContent 和 FPrevContent 之间的不同之处。
// 只能有一处增加或减少的内容，不允有许其他不同。
// ASelStart  : 不同之处的 SelStart，从 1 开始，> 0 表示添加文本，< 0 表示删除文本。
// ASelText   : 不同之处的文本内容
// AHalfEvent : 是否是单个“用户操作”所触发的半个 OnChange 事件。
function THistory.StrDiff1(const ACurContent: string; out ASelStart: SizeInt;
  out ASelText: string; out AHalfEvent: Boolean): Boolean;
var
  BytePos, DiffLen: SizeInt;
begin
  Result := False;

  DiffLen := Length(ACurContent) - Length(FPrevContent);

  BytePos := UTF8PosToBytePos(ACurContent, FMemo.SelStart + 1);

  if DiffLen > 0 then begin          // Add text | 添加文本
    BytePos   := BytePos - DiffLen;
    ASelText  := Copy(ACurContent, BytePos, DiffLen);
    ASelStart := FMemo.SelStart - UTF8LengthFast(ASelText) + 1;
    // Special case: drag in from other control
    // 特殊情况：从其它控件拖入
    if ASelStart - 1 <> FPrevSelStart then begin
      Result := StrDiff2(AcurContent, ASelStart, ASelText, AHalfEvent);
      Exit;
    end;
  end else if DiffLen < 0 then begin // Ddelete text | 删除文本
    ASelText  := Copy(FPrevContent, BytePos, -DiffLen);
    ASelStart := -(FMemo.SelStart + 1);
  end else
    Exit;

  Result := True;

  AHalfEvent := FHalfEvent;
  FHalfEvent := True;
end;

// Get the difference between ACurContent and FPrevContent.
// The difference can only be insert or delete text in one place, not allowed other difference.
// ASelStart  : the SelStart of the difference, based 1, > 0 means add text, < 0 means delete content.
// ASelText   : the content of the difference.
// AHalfEvent : is it a half OnChange event of one User Operation.

// 获取 ACurContent 和 FPrevContent 之间的不同之处。
// 只能有一处增加或减少的内容，不允有许其他不同。
// ASelStart  : 不同之处的 SelStart，从 1 开始，> 0 表示添加文本，< 0 表示删除文本。
// ASelText   : 不同之处的文本内容
// AHalfEvent : 是否是单个“用户操作”所触发的半个 OnChange 事件。
function THistory.StrDiff2(const ACurContent: string; out ASelStart: SizeInt;
  out ASelText: string; out AHalfEvent: Boolean): Boolean;
var
  CurStart, PrevStart, CurPos, PrevPos, StopPos: PChar;
  BytePos, CurLen, PrevLen, DiffLen: SizeInt;
begin
  Result := False;

  CurStart  := PChar(ACurContent);
  PrevStart := PChar(FPrevContent);

  // For speed, use Length(string) DO NOT use Length(PChar)
  // 为了提高速度，使用 Length(string) 而不要使用 Length(PChar)
  CurLen  := Length(ACurContent);
  PrevLen := Length(FPrevContent);
  DiffLen := CurLen - PrevLen;

  if DiffLen < 0 then
    StopPos := CurStart + CurLen - 1
  else if DiffLen > 0 then
    StopPos := CurStart + PrevLen - 1
  else
    Exit;

  // Byte-by-byte comparison | 逐字节比较
  CurPos  := CurStart;
  PrevPos := PrevStart;
  while CurPos <= StopPos do begin
    if CurPos^ <> PrevPos^ then Break;
    Inc(CurPos);
    Inc(PrevPos);
  end;

  // Find codepoint start byte | 查找码点起始字节
  while CurPos > CurStart do
    case CurPos^ of
      #0..#127, #192..#247: break;
      else Dec(CurPos);
  end;

  BytePos := CurPos - CurStart + 1;

  if DiffLen > 0 then begin  // Add text | 添加文本
    ASelText  := Copy(ACurContent, BytePos, DiffLen);
    ASelStart := UTF8LengthFast(CurStart, BytePos);
  end else begin             // Delete text | 删除文本
    ASelText  := Copy(FPrevContent, BytePos, -DiffLen);
    ASelStart := -UTF8LengthFast(PrevStart, BytePos);
  end;

  Result := True;

  AHalfEvent := FHalfEvent;
  FHalfEvent := True;
end;

function THistory.CanUndo: Boolean; inline;
begin
  Result := FSteps.FIndex >= 0;
end;

function THistory.CanRedo: Boolean; inline;
begin
  Result := FSteps.FIndex < FSteps.Count - 1;
end;

procedure THistory.Undo;
var
  Half: Integer;
begin
  if FSteps.FIndex < 0 then Exit;

  FInEdit := False;
  FixOnChangeBug := True;

  with FSteps.CurStep^ do begin
    Half := HalfStep;
    if SelStart > 0 then begin
      // writeln(Format('Undo: %d, %s, %d', [SelStart-1, SelText, HalfStep]));
      // From "baseed 1" to "based 0" | 从“1起始”转换到“0起始”
      FMemo.SelStart  := SelStart - 1;
      FMemo.SelLength := UTF8LengthFast(SelText);
      FMemo.SelText   := '';
    end else begin
      // writeln(Format('Undo: %d, %s, %d', [-SelStart-1, SelText, HalfStep]));
      // From "baseed 1" to "based 0" | 从“1起始”转换到“0起始”
      FMemo.SelStart  := -SelStart - 1;
      FMemo.SelLength := 0;
      FMemo.SelText   := SelText;
    end;
  end;
  Dec(FSteps.FIndex);
  FPrevContent := FMemo.Text;

  if FixOnChangeBug then MemoOnChange(FMemo);
  FInEdit := True;

  // Trigger another half Undo operation | 触发另外半个 Undo 操作
  if Half = 2 then Undo;
end;

procedure THistory.Redo;
var
  Half: Integer;
begin
  if FSteps.FIndex >= FSteps.Count - 1 then Exit;
  FInEdit := False;

  FixOnChangeBug := True;

  Inc(FSteps.FIndex);
  with FSteps.CurStep^ do begin
    Half := HalfStep;
    if SelStart > 0 then begin
      // writeln(Format('Redo: %d, %s, %d', [SelStart-1, SelText, HalfStep]));
      // From "baseed 1" to "based 0" | 从“1起始”转换到“0起始”
      FMemo.SelStart  := SelStart - 1;
      FMemo.SelLength := 0;
      FMemo.SelText  := SelText;
    end else begin
      // writeln(Format('Redo: %d, %s, %d', [-SelStart-1, SelText, HalfStep]));
      // From "baseed 1" to "based 0" | 从“1起始”转换到“0起始”
      FMemo.SelStart  := -SelStart - 1;
      FMemo.SelLength := UTF8LengthFast(SelText);
      FMemo.SelText   := '';
    end;
  end;

  FPrevContent := FMemo.Text;

  if FixOnChangeBug then MemoOnChange(FMemo);
  FInEdit := True;

  // Trigger another half Redo operation | 触发另外半个 Redo 操作
  if Half = 1 then Redo;
end;

procedure THistory.PasteText;
var
  ClipBoardText: string;
begin
  ClipBoardText := ClipBoard.AsText;
  if ClipBoardText = '' then Exit;

  if FMemo.SelLength > 0 then begin
    FSteps.AddStep(-(FMemo.SelStart+1), FMemo.SelText, False);
    FSteps.AddStep(FMemo.SelStart + 1, ClipBoardText, True);
  end else
    FSteps.AddStep(FMemo.SelStart + 1, ClipBoardText, False);

  FInEdit := False;
  FixOnChangeBug := True;

  FMemo.SelText := ClipBoardText;
  FPrevContent  := FMemo.Text;

  if FixOnChangeBug then MemoOnChange(FMemo);

  FInEdit := True;
end;

procedure THistory.DeleteText;
begin
  if FMemo.SelLength = 0 then Exit;

  FSteps.AddStep(-(FMemo.SelStart+1), FMemo.SelText, False);

  FInEdit := False;
  FixOnChangeBug := True;

  FMemo.SelText := '';
  FPrevContent  := FMemo.Text;

  if FixOnChangeBug then MemoOnChange(FMemo);

  FInEdit := True;
end;

procedure THistory.Reset; inline;
begin
  FSteps.DelStep(0);
end;

// Do not let external code and THistory write the same memory address
// 不要让外部代码和 THistory 写相同的内存地址
function THistory.GetHistoryData: TSteps;
begin
  if FSteps.Count = 0 then
    Result := nil
  else
    Result := FSteps;
end;

// Do not let external code and THistory write the same memory address
// 不要让外部代码和 THistory 写相同的内存地址
procedure THistory.SetHistoryData(Data: TSteps; const NewContent: string);
begin
  if Assigned(Data) then begin
    if FSteps.Count = 0 then FreeAndNil(FSteps);
    FSteps := Data
  end else if FSteps.Count > 0 then
    // Old history data is kept by external code
    // 旧的历史记录数据由外部代码保管
    FSteps := TSteps.Create;

  FInEdit := False;

  FMemo.Text := NewContent;
  // Do not use "FPrevContent:=PrevContent". In the Windows, "PrevContent<>FMemo.Text".
  // because FMemo.Text use #13#10 as Line-Ending, but PrevContent use #10 as Line-Ending.
  // 不要使用“FPrevContent:=PrevContent”，在 Windows 中，“PrevContent<>FMemo.Text”。
  // 因为 FMemo.Text 使用 #13#10 作为换行符，而 PrevContent 使用 #10 作为换行符。
  FPrevContent := FMemo.Text;

  FInEdit := True;
end;

{ ========== Custom Functions ========== }

// Convert the character index of a UTF8 string to a byte index. Returns 0 if
// UPos <= 0, return Size + 1 if UPos > Size. This function does not check the
// integrity of the UTF8 encoding, does not support multi-codepoint character,
// the multi-codepoint character will be treated as multiple characters.

// 将 UTF8 字符串的字符索引转换为字节索引， 如果 UPos <= 0，则返回 0，
// 如果 UPos > Size，则返回 Size + 1。本函数不检查 UTF8 编码的完整性，
// 不支持多码点字符，多码点字符会被当成多个字符处理。

// Text         : UTF8 string | UTF8 字符串
// Size         : The bytes size of UTF8 string | UTF8 字符串的字节长度
// UPos         : Index of character, based 1 | 字符索引，从 1 开始
// Return Value : Byte index of UPos, based 1 | UPos 对应的字节索引，从 1 开始
function UTF8PosToBytePos(const Text: PChar; const Size: SizeInt; UPos: SizeInt): SizeInt;
begin
  Result := 0;
  if UPos <= 0 then Exit;

  while (UPos > 1) and (Result < Size) do begin
    case Text[Result] of
      // #0  ..#127: Inc(Pos);
      #192..#223: Inc(Result, 2);
      #224..#239: Inc(Result, 3);
      #240..#247: Inc(Result, 4);
      else Inc(Result);
    end;
    Dec(UPos);
  end;

  Inc(Result);
end;

function UTF8PosToBytePos(const Text: String; const UPos: SizeInt): SizeInt; inline;
begin
  Result := UTF8PosToBytePos(PChar(Text), Length(Text), UPos);
end;

// Get characters count of a UTF8 string. This function does not check the integrity
// of the UTF8 encoding, Does not support multi-codepoint character, the multi-codepoint
// character will be treated as multiple characters.

// 获取 UTF8 字符串中字符的个数。本函数不检查 UTF8 编码的完整性。不支持多码点字符，多码点
// 字符会被当成多个字符对待。
function UTF8LengthFast(const Text: PChar; const Size: SizeInt): SizeInt;
var
  Pos: Integer;
begin
  Result := 0;
  Pos    := 0;
  while Pos < Size do begin
    case Text[Pos] of
        // #0  ..#127: Inc(Pos);
        #192..#223: Inc(Pos, 2);
        #224..#239: Inc(Pos, 3);
        #240..#247: Inc(Pos, 4);
        else Inc(Pos);
    end;
    Inc(Result);
  end;
end;

function UTF8LengthFast(const AStr: String): SizeInt; inline;
begin
  Result := UTF8LengthFast(PChar(AStr), Length(AStr));
end;

end.

