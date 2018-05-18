unit uResources;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

var

  AppFullName              : string;
  AppName                  : string;
  AppDir                   : string;

const

  AppTitle                 = 'TomiNote';
  AppVersion               = '1.1';

  BrightThemeID            = 1;
  DarkThemeID              = 2;

  DefFontSize              = 12;
  DefExpandSignSize        = 9;

  DefTreeBarPercent        = 25;
  DefRecyBarPercent        = 30;
  DefInfoBarPercent        = 30;

  DefBrightForeColor       = $212121;
  DefBrightBackColor       = $F7F7F7;
  DefDarkForeColor         = $D3D7CF;
  DefDarkBackColor         = $2E3436;

  DBFileExt                = '.tdb';

  EmptyRecyIconID          = 40;
  FullRecyIconID           = 41;

  LockFileExt              = '.tominote_lock';

  DefSearchCountLimit      = 50000;
  DefRecentCountLimit      = 10;

resourcestring

  Res_CaptionOK            = 'OK(&O)';
  Res_CaptionCancel        = 'Cancel(&C)';

  Res_DBVersionError       = 'Database version error!';

  Res_CreateDBFail         = 'Failed to create the database!';
  Res_OpenDBFail           = 'Failed to open the database!';
  Res_SaveDBFail           = 'Failed to save the database!';
  Res_CloseDBFail          = 'Failed to close the database!';

  Res_OverwriteFileTip     = 'The file already exists. Do you want to overwrite it?';
  Res_OverwriteFileFail    = 'Failed to overwrite the file!';

  Res_SaveDataTip          = 'The data has changed. Do you want to save it?';
  Res_DeleteNodeTip        = 'The node can''t be recovered after delete. Do you want to continue?';
  Res_EmptyRecyclerTip     = 'The nodes can''t be recovered after empty. Do you want to continue?';

  Res_DialogFilterTDB      = 'TomiNote File|*.tdb|All File|*.*';
  Res_UnnamedNode          = 'Unnamed Node';
  Res_ChildNodesInfo       = 'Child Nodes: %d';

  Res_CaptionSearch        = 'Search(&S)';
  Res_CaptionReplace       = 'Replace(&R)';

  Res_MultiReplaceTip      = 'Multiple nodes will be changed. Do you want to continue?';

  Res_SearchResultIndex    = 'Search Result: %d / %d';
  Res_ScarchResultPart     = 'Part %d [ %s | %ds ]';
  Res_ScarchResultTotal    = 'Total %d [ %s | %ds ]';

  Res_CaptionImport        = 'Import(&I)';
  Res_CaptionExport        = 'Export(&E)';

  Res_DialogFilterTXT      = 'Text File|*.txt|All File|*.*';
  Res_AutoSaveInfo         = '[ Save: %dm | Backup: %dm ]';

  Res_RecentFileNotExists  = 'The file doesn''t exists. Do you want to remove the menu item?';
  Res_DBIsLocked           = 'Database is locked. Do you want to force open it?';
  Res_BackupDBFail         = 'Failed to backup the database!';

  Res_CaptionExecute       = 'Execute(&E)';

  Res_RenameWarning        = 'Multiple nodes will be renamed and can''t be undone. Do you want to continue?';

implementation

initialization

  AppFullName              := ParamStr(0);
  AppName                  := ExtractFileName(AppFullName);
  AppDir                   := ExtractFilePath(AppFullName);

end.

