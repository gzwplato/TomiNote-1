unit uTreeDB;

{$mode objfpc}{$H+}

// String constants and string literals require this option
// 字符串常量和字符串字面量需要此选项
{$codepage UTF8}

interface

uses
  Classes, SysUtils, sqlite3dyn, sqlite3conn, sqldb, ComCtrls, IniFiles;

type

  { TDBConfig }

  TDBConfig = class(TObject)
  private
    procedure Put(AValue: string);
    function  Get: string;
  public
    DBVersion: string;
    property Data: string read Get write Put;
  end;

  { TTreeDB }

  TTreeDB = class(TObject)

  private

    FSQLConnection           : TSQLite3Connection;
    FSQLQuery                : TSQLQuery;
    FSQLTransaction          : TSQLTransaction;

  public

    Config : TDBConfig;

    constructor Create;
    destructor Destroy; override;

    { Database File And Table 数据库文件和表 }

    function  OpenDB(ADataBaseName: string): Boolean;
    function  SaveDB: Boolean;
    function  CloseDB(SaveData: Boolean; SaveConfig: Boolean=True): Boolean;

  private

    function  TableExists(ATableName: string): Boolean;
    procedure CreateTable;
    procedure InitTable;

    { Basic Read Write 基本读写 }

    procedure SetParent(ID: Integer; ParentID: Integer);
    procedure SetChildren(ID: Integer; Children: TBoundArray);

  public

    function  GetParent(ID: Integer): Integer;
    function  GetChildren(ID: Integer): TBoundArray;

    function  GetName(ID: Integer): string;
    procedure SetName(ID: Integer; Name: string);

    function  GetNote(ID: Integer): string;
    procedure SetNote(ID: Integer; Note: string);

  private

    { Add And Delete 添加和删除 }

    function  CreateNode(Name, Note: string): Integer;
    function  ReuseNode: Integer;

  public

    function  AddNode(Name, Note: string; ToID: Integer; Mode: TNodeAttachMode): Integer;
    procedure DeleteNode(ID: Integer; IncludeEntry: Boolean = True);
    function  CollectNodes(ID: Integer; IncludeEntry: Boolean = True): TBoundArray;

  private

    { Attach And Detach 停靠和脱离 }

    procedure AttachNode(ID: Integer; ToID: Integer; Mode: TNodeAttachMode);
    procedure DetachNode(ID: Integer);

  public

    { Recycle And Restore 回收和恢复 }

    procedure RecycleNode(ID: Integer);
    procedure RestoreNode(ID: Integer);
    procedure EmptyRecycler;

    { Move 移动 }

    function  MoveNode(ID, ToID: Integer; Mode: TNodeAttachMode): Boolean;
    procedure MoveNodeUp(ID: Integer);
    procedure MoveNodeDown(ID: Integer);
    function  MoveNodeLeft(ID: Integer): Boolean;
    function  MoveNodeRight(ID: Integer; Expand: Boolean): Boolean;

  private

    function HasAsParent(ID, ParentID: Integer): Boolean;

  public

    { Copy 复制 }

    function CopyNode(ID, ToID: Integer; Mode: TNodeAttachMode): Integer;

  end;

const

  TableNote                = 'tnote';
  FieldParent              = 'parent';
  FieldChildren            = 'children';
  FieldName                = 'name';
  FieldNote                = 'note';

const

  { Fixed ID 固定 ID }

  FreeID                   = 0;
  RootID                   = 1;
  RecyclerID               = 2;
  ReuseID                  = 3;
  ConfigID                 = 4;
  SpareID                  = 5;
  FirstID                  = 6;

  AllDepth                 = -1;
  WholeTree                = -2;

  DatabaseVersion          = '1.0';

implementation

{ ============================================================ }
{ Custom Function 自定义函数                                   }
{ ============================================================ }

// Insert an element into integer array
// 向整数数组中插入元素
function ArrayInsert(Arr: TBoundArray; Index: Integer; Element: Integer): TBoundArray;
begin
  SetLength(Arr, Length(Arr) + 1);
  if High(Arr) > Index then
    Move(Arr[Index], Arr[Index + 1], (High(Arr) - Index) * Sizeof(Integer));
  Arr[Index] := Element;
  Result :=Arr;
end;

// Remove an element from integer array
// 从整数数组中删除元素
function ArrayRemove(Arr: TBoundArray; Index: Integer): TBoundArray;
begin
  if Index < High(Arr) then
    Move(Arr[Index + 1], Arr[Index], (High(Arr) - Index) * Sizeof(Integer));
  SetLength(Arr, Length(Arr) - 1);
  Result := Arr;
end;

// Get the index of the element in the array
// 获取元素在数组中的索引
function ArrayIndex(Arr: TBoundArray; Element: Integer; DefIndex: Integer): Integer;
begin
  for Result := Low(Arr) to High(Arr) do
    if Arr[Result] = Element then
      Break;
  if Result > High(Arr) then Result := DefIndex;
end;

// Insert an element into integer array with specific mode
// 以指定模式将元素插入到数组中
function ArrayInsertSpecial(Arr: TBoundArray; Index: Integer; Element: Integer;
  Mode: TNodeAttachMode): TBoundArray;
begin
  case Mode of
    naInsert:
      Result := ArrayInsert(Arr, Index, Element);
    naInsertBehind:
      Result := ArrayInsert(Arr, Index + 1, Element);
    naAddFirst, naAddChildFirst:
      Result := ArrayInsert(Arr, Low(Arr), Element);
    naAdd, naAddChild:
      Result := ArrayInsert(Arr, High(Arr) + 1, Element);
    else
      Result := nil;
  end;
end;

// Remove an element from integer array by its value.
// 从整数数组中删除指定值的元素
function ArrayRemoveByValue(Arr: TBoundArray; Element: Integer): TBoundArray;
var
  Index: Integer;
begin
  Result := Arr;
  Index := ArrayIndex(Arr, Element, -1);
  if Index <> -1 then
    Result := ArrayRemove(Arr, Index);
end;

// Cut TailArr and append it to the LeadArr
// 将 TailArr 裁切后追加到 LeadArr 的尾部
function ArrayAppend(LeadArr, TailArr: TBoundArray;
  TailStart: Integer; TailEnd: Integer = -1): TBoundArray;
var
  LeadLen: Integer;
begin
  LeadLen := Length(LeadArr);
  if TailEnd < 0 then TailEnd := Length(TailArr);
  SetLength(LeadArr, LeadLen + TailEnd - TailStart);
  if TailStart < High(TailArr) then
    Move(TailArr[TailStart], LeadArr[LeadLen], (TailEnd - TailStart) * Sizeof(Integer));
  Result := LeadArr;
end;

// Get the pointer to the Length field (hidden field) of an array
// 获取指向数组的长度字段（隐藏字段）的指针
function GetArrayHighField(PArr: Pointer): PDynArrayIndex; inline;
begin
  // See TDynArray in dynarr.inc | 参阅 dynarr.inc 中的 TDynArray
  Result := PArr - SizeOf(IntPtr);
end;

// Convert an integer array to a byte array
// 将整数数组转换为字节数组
function IntsToBytes(const Ints: TBoundArray): TBytes;
begin
  if Assigned(Ints) then
    GetArrayHighField(@Ints[0])^ := Length(Ints) * SizeOf(Ints[0]) - 1;
  Result := TBytes(Ints);
end;

// Convert an byte array to a integer array
// 将字节数组转换为整数数组
function BytesToInts(const Bytes: TBytes): TBoundArray;
begin
  if Assigned(Bytes) then
    GetArrayHighField(@Bytes[0])^ := Length(Bytes) div SizeOf(TBoundArray[0]) - 1;
  Result := TBoundArray(Bytes);
end;

{ ============================================================ }
{ TTreeDB 树形数据库                                           }
{ ============================================================ }

constructor TTreeDB.Create;
begin
  inherited Create;

  FSQLConnection  := TSQLite3Connection.Create(nil);
  FSQLTransaction := TSQLTransaction.Create(nil);
  FSQLQuery       := TSQLQuery.Create(nil);

  Config := TDBConfig.Create;
end;

destructor TTreeDB.Destroy;
begin
  Config.Free;

  FreeAndNil(FSQLQuery);
  FreeAndNil(FSQLTransaction);
  FreeAndNil(FSQLConnection);

  inherited Destroy;
end;

{ ============================================================ }
{ Database File And Table 数据库文件和表                       }
{ ============================================================ }

function TTreeDB.OpenDB(ADataBaseName: string): Boolean;
begin
  Result := False;
  if FSQLConnection.Connected then Exit;

  FSQLConnection.DatabaseName := ADataBaseName;
  try
    FSQLConnection.Open;
    FSQLConnection.Transaction := FSQLTransaction;
    FSQLTransaction.DataBase   := FSQLConnection;
    FSQLQuery.DataBase         := FSQLConnection;

    CreateTable;
    FSQLTransaction.Active := True;

    Config.Data := GetNote(ConfigID);
    Result := True;
  except
  end;
end;

function TTreeDB.SaveDB: Boolean;
begin
  Result := True;
  if FSQLTransaction.Active then
    try
      FSQLTransaction.Commit;
      FSQLTransaction.Active := True;
    except
      Result := False;
    end;
end;

function TTreeDB.CloseDB(SaveData: Boolean; SaveConfig: Boolean=True): Boolean;
begin
  Result := False;
  if SaveData then begin
    if not SaveDB then Exit;
  end else
    FSQLTransaction.Rollback;

  if SaveConfig then begin
    FSQLTransaction.Active := True;
    SetNote(ConfigID, Config.Data);
    FSQLTransaction.Commit;
  end;

  FSQLConnection.Close;
  FSQLConnection.Transaction := nil;
  FSQLTransaction.DataBase   := nil;
  FSQLQuery.DataBase         := nil;

  Result := not FSQLConnection.Connected;
end;

procedure TTreeDB.CreateTable;
begin
  if not TableExists(TableNote) then
  begin
    FSQLTransaction.Active := True;
    FSQLConnection.ExecuteDirect(Format('Create Table "%s"(' +
      ' "%s" Integer Not Null,' +
      ' "%s" Blob,' +
      ' "%s" Text,' +
      ' "%s" Text);',
      [TableNote, FieldParent, FieldChildren, FieldName, FieldNote]));
    // Write Fixed ID | 写入固定 ID
    InitTable;
    // Write database version | 写入数据库版本
    Config.DBVersion := DatabaseVersion;
    SetNote(ConfigID, Config.Data);

    FSQLTransaction.Commit;
  end;
end;

function TTreeDB.TableExists(ATableName: string): Boolean;
var
  TableNames: TStringList;
begin
  Result := False;
  TableNames := TStringList.Create;

  FSQLConnection.GetTableNames(TableNames);

  Result := TableNames.IndexOf(ATableName) >= 0;
  TableNames.Free;
end;

procedure TTreeDB.InitTable;
begin
  CreateNode('Root', '');
  CreateNode('Recycler', '');
  CreateNode('Reuse', '');
  CreateNode('Config', '');
  CreateNode('Spare', '');
end;

{ ============================================================ }
{ Basic Read Write 基本读写                                    }
{ ============================================================ }

function TTreeDB.GetParent(ID: Integer): Integer;
begin
  FSQLQuery.SQL.Text := Format('Select %s From %s where rowid=:rowid', [FieldParent, TableNote]);
  FSQLQuery.Params.ParamByName('rowid').AsInteger := ID;
  FSQLQuery.Open;
  Result := FSQLQuery.Fields[0].AsInteger;
  FSQLQuery.Close;
end;

procedure TTreeDB.SetParent(ID: Integer; ParentID: Integer);
begin
  FSQLQuery.SQL.Text := Format('Update %s Set %s=:parent Where rowid=:rowid', [TableNote, FieldParent]);
  FSQLQuery.Params.ParamByName('parent').AsInteger := ParentID;
  FSQLQuery.Params.ParamByName('rowid').AsInteger := ID;
  FSQLQuery.ExecSQL;
end;

function TTreeDB.GetChildren(ID: Integer): TBoundArray;
begin
  FSQLQuery.SQL.Text := Format('Select %s From %s where rowid=:rowid', [FieldChildren, TableNote]);
  FSQLQuery.Params.ParamByName('rowid').AsInteger := ID;
  FSQLQuery.Open;
  Result := BytesToInts(FSQLQuery.Fields[0].AsBytes);
  FSQLQuery.Close;
end;

procedure TTreeDB.SetChildren(ID: Integer; Children: TBoundArray);
var
  BChildren: TBytes;
begin
  BChildren := IntsToBytes(Children);
  FSQLQuery.SQL.Text := Format('Update %s Set %s=:children Where rowid=:rowid', [TableNote, FieldChildren]);
  FSQLQuery.Params.ParamByName('children').AsBytes := BChildren;
  FSQLQuery.Params.ParamByName('rowid').AsInteger := ID;
  FSQLQuery.ExecSQL;
  // Restore the length of the array to the state before it was passed in
  // 恢复传入时的数组长度信息
  BytesToInts(BChildren);
end;

function TTreeDB.GetName(ID: Integer): string;
begin
  FSQLQuery.SQL.Text := Format('Select %s From %s where rowid=:rowid', [FieldName, TableNote]);
  FSQLQuery.Params.ParamByName('rowid').AsInteger := ID;
  FSQLQuery.Open;
  Result := FSQLQuery.Fields[0].AsString;
  FSQLQuery.Close;
end;

procedure TTreeDB.SetName(ID: Integer; Name: string);
begin
  FSQLQuery.SQL.Text := Format('Update %s Set %s=:name Where rowid=:rowid', [TableNote, FieldName]);
  FSQLQuery.Params.ParamByName('name').AsString := Name;
  FSQLQuery.Params.ParamByName('rowid').AsInteger := ID;
  FSQLQuery.ExecSQL;
end;

function TTreeDB.GetNote(ID: Integer): string;
begin
  FSQLQuery.SQL.Text := Format('Select %s From %s where rowid=:rowid', [FieldNote, TableNote]);
  FSQLQuery.Params.ParamByName('rowid').AsInteger := ID;
  FSQLQuery.Open;
  Result := FSQLQuery.Fields[0].AsString;
  FSQLQuery.Close;
end;

procedure TTreeDB.SetNote(ID: Integer; Note: string);
begin
  FSQLQuery.SQL.Text := Format('Update %s Set %s=:note Where rowid=:rowid', [TableNote, FieldNote]);
  FSQLQuery.Params.ParamByName('note').AsString := Note;
  FSQLQuery.Params.ParamByName('rowid').AsInteger := ID;
  FSQLQuery.ExecSQL;
end;

{ ============================================================ }
{ TDBConfig 数据库配置信息                                     }
{ ============================================================ }

function TDBConfig.Get: string;
var
  AStream: TStringStream;
  IniFile: TIniFile;
begin
  AStream := TStringStream.Create('');

  IniFile := TIniFile.Create(TStream(AStream));
  IniFile.WriteString ('Config', 'Version', DBVersion);
  IniFile.Free;

  Result := AStream.DataString;
  AStream.Free;
end;

procedure TDBConfig.Put(AValue: string);
var
  AStream: TStringStream;
  IniFile: TIniFile;
begin
  AStream := TStringStream.Create(AValue);

  IniFile := TIniFile.Create(TStream(AStream));
  DBVersion           := IniFile.ReadString ('Config', 'Version', '');
  IniFile.Free;

  AStream.Free;
end;

{ ============================================================ }
{ Add And Delete 添加和删除                                    }
{ ============================================================ }

function TTreeDB.CreateNode(Name, Note: string): Integer;
begin
  FSQLQuery.SQL.Text :=
    Format('Insert Into %s (%s, %s, %s) Values (:parent, :name, :note)',
      [TableNote, FieldParent, FieldName, FieldNote]);
  FSQLQuery.Params.ParamByName('parent').AsInteger := FreeID;
  FSQLQuery.Params.ParamByName('name').AsString := Name;
  FSQLQuery.Params.ParamByName('note').AsString := Note;
  FSQLQuery.ExecSQL;

  // Get the ID of the last inserted record
  // 获取最后插入的记录的 ID
  FSQLQuery.SQL.Text := Format('Select last_insert_rowid() From %s', [TableNote]);
  FSQLQuery.Open;
  Result := FSQLQuery.Fields[0].AsInteger;
  FSQLQuery.Close;
end;

// Reuse a node from ReuseID | 从 ReuseID 中重用一个节点
function TTreeDB.ReuseNode: Integer;
var
  Index: Integer;
  Children: TBoundArray;
begin
  // The Index of the last reused node | 上次重用的节点的索引
  Index := GetParent(ReuseID) - 1;
  Children := GetChildren(ReuseID);
  if Assigned(Children) and (Index < High(Children)) then begin
    Inc(Index);
    Result := Children[Index];

    SetParent(Result, FreeID);
    SetChildren(Result, nil);
    SetName(Result, '');
    SetNote(Result, '');

    SetParent(ReuseID, Index + 1);
  end else
    Result := -1;
end;

function TTreeDB.AddNode(Name, Note: string; ToID: Integer; Mode: TNodeAttachMode): Integer;
begin
  Result := ReuseNode;
  if Result = -1 then
    Result := CreateNode(Name, Note)
  else begin
    SetName(Result, Name);
    SetNote(Result, Note);
  end;
  AttachNode(Result, ToID, Mode);
end;

// Remove node and its all children to ReuseID
// 删除一个节点及其子节点到 ReuseID
procedure TTreeDB.DeleteNode(ID: Integer; IncludeEntry: Boolean = True);
var
  Children, ReuseChildren: TBoundArray;
  ReuseIndex, ReuseLen: Integer;
begin
  if (ID < FirstID) and IncludeEntry then Exit;

  Children := CollectNodes(ID, IncludeEntry);

  ReuseIndex := GetParent(ReuseID) - 1;
  ReuseChildren := GetChildren(ReuseID);

  // Get nodes that have not been reused | 获取尚未重用的节点
  ReuseLen := High(ReuseChildren) - ReuseIndex;
  if (ReuseLen > 0) and (ReuseIndex >= 0) then
    Move(ReuseChildren[ReuseIndex + 1], ReuseChildren[0], ReuseLen * Sizeof(Integer));
  // Append the deleted nodes to the end of the nodes that have not been reused
  // 将被删除的节点添加到未重用的节点之后
  SetLength(ReuseChildren, ReuseLen + Length(Children));
  if Assigned(Children) then
    Move(Children[0], ReuseChildren[ReuseLen], Length(Children) * Sizeof(Integer));
  // Write all these nodes into ReuseID | 将所有这些节点写入ReuseID
  SetChildren(ReuseID, ReuseChildren);
  SetParent(ReuseID, 0);

  if IncludeEntry then
    DetachNode(ID)
  else
    SetChildren(ID, nil);
end;

// Collect node and its all descendant nodes | 收集节点及其所有子孙节点
function TTreeDB.CollectNodes(ID: Integer; IncludeEntry: Boolean = True): TBoundArray;
var
  Index: Integer;

  procedure DoCollectNodes(Children: TBoundArray);
  var
    Child: Integer;
  begin
    for Child in Children do begin
      // Auto expansion buffer | 自动扩充缓冲区
      if Index > High(Result) then
        SetLength(Result, Length(Result) + 100);
      Result[Index] := Child;
      Inc(Index);
      DoCollectNodes(GetChildren(Child));
    end;
  end;

begin
  if (ID < FirstID) and IncludeEntry then Exit;

  // Initialize buffer capacity to 8 | 将缓冲区容量初始化为8
  SetLength(Result, 8);
  if IncludeEntry then begin
    Result[0] := ID;
    Index := 1;
  end else
    Index := 0;
  DoCollectNodes(GetChildren(ID));
  // Remove extra buffer space | 删除多余的缓冲区空间
  SetLength(Result, Index);
end;

{ ============================================================ }
{ Attach And Detach 停靠和脱离                                 }
{ ============================================================ }

// Attach a node on the tree | 将一个节点停靠在树上
procedure TTreeDB.AttachNode(ID: Integer; ToID: Integer; Mode: TNodeAttachMode);
var
  ToIndex: Integer;
  ParentID: Integer;
  Children: TBoundArray;
begin
  if ID < FirstID then Exit;

  ToIndex := 0;
  ParentID := 0;
  Children := nil;

  // If the attached target is a special node, convert the attach mode to the Child Node mode
  // 如果停靠目标是特殊节点，则将停靠模式转换为子节点模式
  if ToID < FirstID then
    case Mode of
      naAddFirst, naInsert:  Mode := naAddChildFirst;
      naAdd, naInsertBehind: Mode := naAddChild;
    end;

  case Mode of
    naInsert, naInsertBehind:
    begin
      ParentID := GetParent(ToID);
      Children := GetChildren(ParentID);
      // Get the insert position | 获取插入位置
      ToIndex := ArrayIndex(Children, ToID, 0);
    end;

    naAdd, naAddFirst:
    begin
      ParentID := GetParent(ToID);
      Children := GetChildren(ParentID);
    end;

    naAddChild, naAddChildFirst:
    begin
      ParentID := ToID;
      Children := GetChildren(ParentID);
    end;
  end;

  // Add the free node to parent node | 将自由节点添加到父节点中
  SetParent(ID, ParentID);
  Children := ArrayInsertSpecial(Children, ToIndex, ID, Mode);
  SetChildren(ParentID, Children);
end;

// Detach a node from the tree | 将一个节点从树上脱离
procedure TTreeDB.DetachNode(ID: Integer);
var
  ParentID: Integer;
  Children: TBoundArray;
begin
  if ID < FirstID then Exit;

  // Remove itself from the parent | 从父节点中删除自身
  ParentID := GetParent(ID);
  Children := ArrayRemoveByValue(GetChildren(ParentID), ID);
  SetChildren(ParentID, Children);

  // Set itself as a free node | 设置自身为自由节点
  SetParent(ID, FreeID);
end;

{ ============================================================ }
{ Recycle And Restore 回收和恢复                               }
{ ============================================================ }

procedure TTreeDB.RecycleNode(ID: Integer);
begin
  MoveNode(ID, RecyclerID, naAddChild);
end;

procedure TTreeDB.RestoreNode(ID: Integer);
begin
  MoveNode(ID, RootID, naAddChild);
end;

procedure TTreeDB.EmptyRecycler;
begin
  DeleteNode(RecyclerID, False);
end;

{ ============================================================ }
{ Move 移动                                                    }
{ ============================================================ }

function TTreeDB.MoveNode(ID, ToID: Integer; Mode: TNodeAttachMode): Boolean;
begin
  Result := False;

  // In order to improve efficiency, check is performed by external code
  // 为了提高效率，由外部代码执行检查
  // if HasAsParent(ToID, ID) then Exit;

  DetachNode(ID);
  AttachNode(ID, ToID, Mode);
  Result := True;
end;

procedure TTreeDB.MoveNodeUp(ID: Integer);
var
  ParentID: Integer;
  Siblings: TBoundArray;
  Index: Integer;
begin
  if ID < FirstID then Exit;
  ParentID := GetParent(ID);
  Siblings := GetChildren(ParentID);
  if Length(Siblings) = 1 then Exit;

  Index := ArrayIndex(Siblings, ID, 0);
  if Index = 0 then begin
    // If move up the first node, then move it to last
    // 首节点前移，将其移动到最后
    Move(Siblings[1], Siblings[0], High(Siblings) * SizeOf(Integer));
    Siblings[High(Siblings)] := ID;
  end else begin
    // If move up the non-first node, then swap it with the previous node.
    // 非首节点前移，与前一个节点交换位置
    Siblings[Index] := Siblings[Index - 1];
    Siblings[Index - 1] := ID;
  end;

  SetChildren(ParentID, Siblings);
end;

procedure TTreeDB.MoveNodeDown(ID: Integer);
var
  ParentID: Integer;
  Siblings: TBoundArray;
  Index: Integer;
begin
  if ID < FirstID then Exit;
  ParentID := GetParent(ID);
  Siblings := GetChildren(ParentID);
  if Length(Siblings) = 1 then Exit;

  Index := ArrayIndex(Siblings, ID, 0);
  if Index = High(Siblings) then begin
    // If move down the last node, then move it to first.
    // 尾节点后移，将其移动到最前
    Move(Siblings[0], Siblings[1], High(Siblings) * SizeOf(Integer));
    Siblings[0] := ID;
  end else begin
    // If move down the non-last node, then swap it with the next node.
    // 非尾节点后移，与后一个节点交换位置
    Siblings[Index] := Siblings[Index + 1];
    Siblings[Index + 1] := ID;
  end;

  SetChildren(ParentID, Siblings);
end;

function TTreeDB.MoveNodeLeft(ID: Integer): Boolean;
var
  ParentID, StartIndex, FollowIndex: Integer;
  Children, ParentChildren: TBoundArray;
begin
  Result := False;
  if ID < FirstID then Exit;
  ParentID := GetParent(ID);
  if ParentID < FirstID then Exit;

  ParentChildren := GetChildren(ParentID);
  StartIndex := ArrayIndex(ParentChildren, ID, 0);

  // Move the nodes after itself to the tail of its children
  // 将自身之后的节点移到自身子节点尾部
  for FollowIndex := StartIndex + 1 to High(ParentChildren) do
    SetParent(ParentChildren[FollowIndex], ID);

  Children := ArrayAppend(GetChildren(ID), ParentChildren, StartIndex + 1);
  SetChildren(ID, Children);
  // Also remove itself | 同时移除自身
  SetLength(ParentChildren, StartIndex);
  SetChildren(ParentID, ParentChildren);

  // Move itself to the behind of the parent node
  // 将自身移到父节点之后
  AttachNode(ID, ParentID, naInsertBehind);

  Result := True;
end;

function TTreeDB.MoveNodeRight(ID: Integer; Expand: Boolean): Boolean;
var
  PrevID, StartIndex, Index: Integer;
  Children, ParentChildren: TBoundArray;
begin
  Result := False;
  if ID < FirstID then Exit;
  ParentChildren := GetChildren(GetParent(ID));
  StartIndex := ArrayIndex(ParentChildren, ID, 0);
  if StartIndex = 0 then Exit;

  PrevID := ParentChildren[StartIndex - 1];

  // Move itself to the tail of the previous node's children
  // 将自身移到前一节点的子节点尾部
  MoveNode(ID, PrevID, naAddChild);

  if Expand then begin
    // Move its children behind itself
    // 将自身的子节点移到自身之后
    ParentChildren := GetChildren(PrevID);
    Children := GetChildren(ID);

    for Index := 0 to High(Children) do
      SetParent(Children[Index], PrevID);
    SetChildren(ID, nil);

    ParentChildren := ArrayAppend(ParentChildren, Children, 0);
    SetChildren(PrevID, ParentChildren);
  end;

  Result := True;
end;

// Check if ParentID is an ancestor node of ID
// 检查 ParentID 是否为 ID 的祖先节点
function TTreeDB.HasAsParent(ID, ParentID: Integer): Boolean;
var
  CheckID: Integer;
begin
  Result := True;
  CheckID := GetParent(ID);
  while CheckID >= FirstID do begin
    if CheckID = ParentID then Exit;
    CheckID := GetParent(CheckID);
  end;
  Result := CheckID = ParentID;
end;

{ ============================================================ }
{ Copy 复制                                                    }
{ ============================================================ }

function TTreeDB.CopyNode(ID, ToID: Integer; Mode: TNodeAttachMode): Integer;
var
  Child: Integer;
begin
  Result := AddNode(GetName(ID), GetNote(ID), ToID, Mode);

  for Child in GetChildren(ID) do
    CopyNode(Child, Result, naAddChild);
end;

{ ============================================================ }
{ Unit Initialization 单元初始化                               }
{ ============================================================ }

var
  LibFile: string;

initialization

  // Please put the SQLite3 dynamic link library file into the "lib" directory.
  // 请将 SQLite3 的动态链接库文件放到 lib 目录中
{$ifdef MSWINDOWS}
  LibFile := ConcatPaths([ExtractFileDir(ParamStr(0)), 'lib', 'sqlite3.dll']);
{$else}
  LibFile := ConcatPaths([ExtractFileDir(ParamStr(0)), 'lib', 'libsqlite3.so']);
{$endif}

  // Specify a dynamic link library file for the SQLite3 control, if not specified,
  // use the system default dynamic link library file.
  // 为 SQLite3 控件指定一个动态链接库文件，如果未指定，则使用系统默认的动态链接库文件
  if FileExists(LibFile) then
    SQLiteDefaultLibrary := LibFile;

end.

