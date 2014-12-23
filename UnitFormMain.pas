{*******************************************************}
{                     主窗体单元                        }
{*******************************************************}
{*******************************************************}
{ 本软件使用MIT协议.                                    }
{ 发布本软件的目的是希望它能够在一定程度上帮到您.       }
{ 编写者: Vowstar <vowstar@gmail.com>, NODEMCU开发组.   }
{*******************************************************}
unit UnitFormMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, StrUtils, StdCtrls, Richedit,
  ActnList, StdActns, Math, ComCtrls, Actions, Vcl.ImgList,
  {System.AnsiStrings,}
  Vcl.Imaging.PNGImage, Vcl.Imaging.GIFImg, Vcl.Buttons,
  SerialPortsCtrl, SPComm, DelphiZxingQRCode, UnitFrameConfigLine,
  IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient, IdHTTP;

type
  TRunState = (StateHandshake, StateBurn, StateRun, StateFinished);

  TFormMain = class(TForm)
    PanelControlPanel: TPanel;
    ActionListStandard: TActionList;
    FileExit: TFileExit;
    ActionBurn: TAction;
    TimerFindPorts: TTimer;
    LabelCopyRight: TLabel;
    PageControlMain: TPageControl;
    TabSheetOperation: TTabSheet;
    LabelDevA: TLabel;
    ComboBoxSerialPortA: TComboBox;
    ButtonBurn: TButton;
    TabSheetLog: TTabSheet;
    MemoOutput: TMemo;
    TimerStateMachine: TTimer;
    ImageStatus: TImage;
    ProgressBarStatus: TProgressBar;
    LabelStatus: TLabel;
    TabSheetIntroduction: TTabSheet;
    LabelIntroduction: TLabel;
    TabSheetConfig: TTabSheet;
    GridPanelConfig: TGridPanel;
    FrameConfigLine1: TFrameConfigLine;
    FrameConfigLine2: TFrameConfigLine;
    FrameConfigLine3: TFrameConfigLine;
    FrameConfigLine4: TFrameConfigLine;
    FrameConfigLine5: TFrameConfigLine;
    FrameConfigLine6: TFrameConfigLine;
    FrameConfigLine7: TFrameConfigLine;
    PanelQRCode: TPanel;
    ImageQRCode: TImage;
    LabeledEditAPMAC: TLabeledEdit;
    LabeledEditSTAMAC: TLabeledEdit;
    IdHTTPNote: TIdHTTP;
    RichEditNote: TRichEdit;
    TimerCode: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure ActionBurnExecute(Sender: TObject);
    procedure FormDestroy(Sender: TObject);

    procedure TimerFindPortsTimer(Sender: TObject);
    procedure MemoOutputChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure TimerStateMachineTimer(Sender: TObject);
    procedure LabelIntroductionClick(Sender: TObject);
    procedure TimerCodeTimer(Sender: TObject);
  private
    SerailBufferA: AnsiString;
    BurnOK: Boolean;
    RunState: TRunState;
    LastOperationSuccess: Boolean;
    IsThreadStarted: Boolean;
    CurrentAddress: UInt32;
    APMACStr: string;
    STAMACStr: string;
    procedure ReceiveData(Sender: TObject; Buffer: PAnsiChar;
      BufferLength: Word);
    function SendByte(const Data: Byte): Boolean;
    function SendString(const Str: AnsiString): Boolean;
    function GetUnixString(const Str: AnsiString): AnsiString;
    function GetUnicodeHex(const Str: AnsiString): String;
    function GetExchangedString(const Str: AnsiString): AnsiString;
    function GetXorCheck(const Str: AnsiString): UInt8;
    function GetBufferCleanTail(const Buffer: AnsiString): AnsiString;
    function SendStringCleanTail(const Str: AnsiString): Boolean;
    procedure SleepNonBlock(milliseconds: Cardinal);
    procedure FlashImage;
    procedure ChangeIconWait;
    procedure ChangeIconSuccess;
    procedure ChangeIconFail;
    procedure GetRegValue(Frame: AnsiString);
    procedure UpdateQRCode(QRText: String);
    procedure LoadSettings;
    procedure WriteMACFile(const MACStr: string; const FileName: string);
    { Private declarations }
  public
    { Public declarations }
  end;

var
  FormMain: TFormMain;
  CommMain: TComm;

implementation

uses UnitESP8266Protocol;

{$R *.dfm}

procedure TFormMain.ChangeIconFail;
var
  Image: TPngImage;
begin
  Image := TPngImage.Create;
  try
    Image.LoadFromResourceName(Hinstance, 'NO');
    ImageStatus.Picture.Graphic := Image;
  finally
    Image.Free;
  end;
end;

procedure TFormMain.ChangeIconWait;
var
  Image: TGIFImage;
  ResStream: TResourceStream;
begin
  Image := TGIFImage.Create;
  try
    ResStream := TResourceStream.Create(Hinstance, 'WAIT', PChar('BIN'));
    Image.LoadFromStream(ResStream);
    ImageStatus.Picture.Graphic := Image;
    TGIFImage(ImageStatus.Picture.Graphic).Animate := True;
    ResStream.Free;
  finally
    Image.Free;
  end;
end;

procedure TFormMain.ChangeIconSuccess;
var
  Image: TPngImage;
begin
  Image := TPngImage.Create;
  try
    Image.LoadFromResourceName(Hinstance, 'YES');
    ImageStatus.Picture.Graphic := Image;
  finally
    Image.Free;
  end;
end;

procedure TFormMain.FlashImage;
var
  FrameConfigLine: TFrameConfigLine;
  MemoryStream: TMemoryStream;
  RawByte: AnsiString;
  Buffer: AnsiString;
  BaseAddress: UInt32;
  TimeOutCounter: Integer;
  I: Integer;
  J: Integer;
  TrueSize: Integer;
  procedure ReadReg(Address: UInt32);
  begin
    RawByte := '';
    RawByte := ESP_READ_REG;
    PESPReadReg(@RawByte[1])^.RegAddr := Address;
    TThread.Synchronize(nil,
      procedure
      begin
        LastOperationSuccess := False;
        CurrentAddress := Address;
      end);
    SendString(RawByte);
    // TThread.Synchronize(nil,
    // procedure
    // begin
    // MemoOutput.Lines.Add('SEND:' + GetUnicodeHex(RawByte));
    // end);
    TimeOutCounter := 0;
    while ((not BurnOK) and (not LastOperationSuccess)) do
    begin
      Sleep(10);
      Inc(TimeOutCounter);
      if (TimeOutCounter > 1000) then
      begin
        BurnOK := True;
        TThread.Synchronize(nil,
          procedure
          begin
            MemoOutput.Lines.Add('Error:Read ESP8266 register timeout.');
            ChangeIconFail;
          end);
      end;
    end;
  end;
  procedure FlashStream(MemoryStream: TMemoryStream; BaseAddress: UInt32);
  begin
    MemoryStream.Position := 0;
    if (not BurnOK) then
    begin
      RawByte := '';
      RawByte := ESP_SET_BASE_ADDRESS;
      PEspSetBaseAddress(@RawByte[1])^.DataLen :=
        Trunc(4 * Ceil(MemoryStream.Size / 4));
      PEspSetBaseAddress(@RawByte[1])^.Count :=
        Ceil(PEspSetBaseAddress(@RawByte[1])^.DataLen / 1024);
      PEspSetBaseAddress(@RawByte[1])^.BaseAddress := BaseAddress;
      TThread.Synchronize(nil,
        procedure
        begin
          LastOperationSuccess := False;
        end);
      TThread.Queue(nil,
        procedure
        begin
          LabelStatus.Caption := 'Address:' + '0x' + IntToHex(BaseAddress, 5) +
            '  Size:' + IntToStr(Trunc(4 * Ceil(MemoryStream.Size / 4))
            ) + 'Byte';
        end);
      RawByte := MidStr(RawByte, 2, Length(RawByte) - 2);
      RawByte := ESP_PROTOCOL_IDENTIFIER + GetBufferCleanTail(RawByte) +
        ESP_PROTOCOL_IDENTIFIER;
      // TThread.Synchronize(nil,
      // procedure
      // begin
      // MemoOutput.Lines.Add('SEND:' + GetUnicodeHex(RawByte));
      // end);
      SendString(RawByte);
      TimeOutCounter := 0;
      while ((not BurnOK) and (not LastOperationSuccess)) do
      begin
        Sleep(10);
        Inc(TimeOutCounter);
        if (TimeOutCounter > 1000) then
        begin
          BurnOK := True;
          TThread.Synchronize(nil,
            procedure
            begin
              MemoOutput.Lines.Add('Error:Set ESP8266 Address timeout.');
              ChangeIconFail;
            end);
        end;
      end;
      Buffer := '';
      SetLength(Buffer, 1024);
      MemoryStream.Position := 0;
      I := 0;
      TrueSize := MemoryStream.Read((@Buffer[1])^, 1024);
      while ((not BurnOK) and (TrueSize > 0)) do
      begin
        TThread.Synchronize(nil,
          procedure
          begin
            LastOperationSuccess := False;
          end);
        RawByte := '';
        RawByte := ESP_SEND_DATA;
        PEspSendData(@RawByte[1])^.DataLen := Trunc(4 * Ceil(TrueSize / 4));
        PEspSendData(@RawByte[1])^.PacketLen := PEspSendData(@RawByte[1])
          ^.DataLen + 16;
        PEspSendData(@RawByte[1])^.SectorIndex := I;
        SetLength(Buffer, Trunc(4 * Ceil(TrueSize / 4)));
        PEspSendData(@RawByte[1])^.XorCheck := GetXorCheck(Buffer);
        Buffer := GetBufferCleanTail(Buffer);
        RawByte := MidStr(RawByte, 2, Length(RawByte) - 1);
        RawByte := #$C0 + GetBufferCleanTail(RawByte);
        RawByte := RawByte + Buffer + #$C0;
        CommMain.WriteCommData(PAnsiChar(RawByte), Length(RawByte));
        // TThread.Synchronize(nil,
        // procedure
        // begin
        // MemoOutput.Lines.Add('SEND:' + GetUnicodeHex(RawByte));
        // end);
        TimeOutCounter := 0;
        while ((not BurnOK) and (not LastOperationSuccess)) do
        begin
          Sleep(10);
          Inc(TimeOutCounter);
          if (TimeOutCounter > 1000) then
          begin
            BurnOK := True;
            TThread.Queue(nil,
              procedure
              begin
                MemoOutput.Lines.Add('Error:Write flash timeout.');
                ChangeIconFail;
              end);
          end;
        end;
        TrueSize := MemoryStream.Read((@Buffer[1])^, 1024);
        Inc(I);
        if ((MemoryStream.Size > 0) and
          (MemoryStream.Position mod (MemoryStream.Size div 100) <= 1024)) then
          TThread.Synchronize(nil,
            procedure
            begin
              ProgressBarStatus.Position :=
                Round(ProgressBarStatus.Max * MemoryStream.Position /
                MemoryStream.Size);
            end);
      end;
      if (MemoryStream.Size > 0) then
        TThread.Synchronize(nil,
          procedure
          begin
            ProgressBarStatus.Position :=
              Ceil(ProgressBarStatus.Max * MemoryStream.Position /
              MemoryStream.Size);
          end);
    end;
  end;
  function GetMemoryStreamAndBaseAddress(var MemoryStream: TMemoryStream;
  var BaseAddress: UInt32; const FrameConfigLine: TFrameConfigLine): Boolean;
  begin
    Result := False;
    if (FrameConfigLine.GetMemoryStream(MemoryStream) And
      FrameConfigLine.GetBaseAddress(BaseAddress) And FrameConfigLine.Checked)
    then
      Result := True;
  end;

begin
  TThread.Synchronize(nil,
    procedure
    begin
      IsThreadStarted := True;
    end);
  ReadReg($3FF00050);
  ReadReg($3FF00054);
  ReadReg($3FF00058);
  ReadReg($3FF0005C);
  TThread.Synchronize(nil,
    procedure
    begin
      if ((APMACStr <> '') and (STAMACStr <> '')) then
      begin
        UpdateQRCode(' AP MAC:' + APMACStr + #13#10 + 'STA MAC:' + STAMACStr);
        Self.LabeledEditAPMAC.Text := APMACStr;
        Self.LabeledEditSTAMAC.Text := STAMACStr;
        WriteMACFile(FormatdateTime('yyyymmddhhnnss', Now) + #13#10 + ' AP MAC:'
          + APMACStr + #13#10 + 'STA MAC:' + STAMACStr + #13#10,
          'ESP8266MAC.txt');
        ImageQRCode.Picture.SaveToFile
          (FormatdateTime('yyyymmddhhnnss".png"', Now));
      end;
    end);
  for J := 1 to 7 do
  begin
    case J of
      1:
        begin
          FrameConfigLine := FrameConfigLine1;
        end;
      2:
        begin
          FrameConfigLine := FrameConfigLine2;
        end;
      3:
        begin
          FrameConfigLine := FrameConfigLine3;
        end;
      4:
        begin
          FrameConfigLine := FrameConfigLine4;
        end;
      5:
        begin
          FrameConfigLine := FrameConfigLine5;
        end;
      6:
        begin
          FrameConfigLine := FrameConfigLine6;
        end;
      7:
        begin
          FrameConfigLine := FrameConfigLine7;
        end;
    end;
    if (not BurnOK) then
    begin
      MemoryStream := TMemoryStream.Create;;
      if (GetMemoryStreamAndBaseAddress(MemoryStream, BaseAddress,
        FrameConfigLine)) then
        FlashStream(MemoryStream, BaseAddress);
      MemoryStream.Free;
    end;
  end;
  TThread.Queue(nil,
    procedure
    begin
      LabelStatus.Caption := 'Ready';
    end);
  TThread.Synchronize(nil,
    procedure
    begin
      RunState := StateRun;
      IsThreadStarted := False;
    end);
end;

procedure TFormMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  RunState := StateFinished;
  BurnOK := True;
  TimerStateMachine.Enabled := False;
end;

procedure TFormMain.FormCreate(Sender: TObject);
begin
  CommMain := TComm.Create(Self);
  CommMain.OnReceiveData := ReceiveData;
  BurnOK := False;
  RunState := StateFinished;
  LoadSettings;
  LabelCopyRight.Caption := 'NODEMCU TEAM';
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  RunState := StateFinished;
  BurnOK := True;
  CommMain.StopComm;
  CommMain.Free;
end;

function TFormMain.SendByte(const Data: Byte): Boolean;
begin
  if CommMain.WriteCommData(@Data, Sizeof(Data)) then
  begin
    Result := True;
  end
  else
  begin
    Result := False;
  end;
end;

function TFormMain.SendString(const Str: AnsiString): Boolean;
begin
  Result := CommMain.WriteCommData(PAnsiChar(Str), Length(Str));
end;

function TFormMain.SendStringCleanTail(const Str: AnsiString): Boolean;
begin
  Result := SendString(GetBufferCleanTail(Str));
end;

procedure TFormMain.SleepNonBlock(milliseconds: Cardinal);
var
  I: Cardinal;
begin
  if (milliseconds > 50) then
    for I := 0 to (milliseconds div 50) do
    begin
      Sleep(50);
      Application.ProcessMessages;
    end
  else
  begin
    Sleep(50);
    Application.ProcessMessages;
  end;
end;

procedure TFormMain.MemoOutputChange(Sender: TObject);
begin
  // while (MemoOutput.Lines.Count > 100) do
  // begin
  // MemoOutput.Lines.Delete(0);
  // end;
end;

function TFormMain.GetBufferCleanTail(const Buffer: AnsiString): AnsiString;
var
  Temp: AnsiString;
  I: Integer;
  FooContinue: Boolean;
begin
  FooContinue := False;
  for I := 1 to Length(Buffer) do
  begin
    if (Buffer[I] = #$C0) then
    begin
      Temp := Temp + #$DB#$DC;
    end
    else if (Buffer[I] = #$DB) then
    begin
      Temp := Temp + #$DB#$DD;
    end
    else
    begin
      Temp := Temp + Buffer[I];
    end;
    // else
    // begin
    // if (FooContinue) then
    // begin
    // if (Buffer[I] <> #$DD) then
    // begin
    // if (Buffer[I] = #$DC) then
    // begin
    // Temp := Temp + #$DD;
    // end;
    // FooContinue := False;
    // end;
    // end;
    // Temp := Temp + Buffer[I];
    // // DB DD DD DD DD ... DD DC
    // if ((Buffer[I] = #$DB)) then
    // begin
    // FooContinue := True;
    // end;
    // end;
  end;
  Result := Temp;
end;

function TFormMain.GetExchangedString(const Str: AnsiString): AnsiString;
var
  Temp: AnsiString;
  I: Integer;
begin
  I := 1;
  Temp := Str;
  if (Length(Str) mod 2 = 0) then
  begin
    while I < Length(Str) do
    begin
      Temp[I + 1] := Str[I];
      Temp[I] := Str[I + 1];
      I := I + 2;
    end;
  end
  else
    Temp := '';
  Result := Temp;
end;

procedure TFormMain.GetRegValue(Frame: AnsiString);
{$J+}
const
  Reg1: UInt8 = 0;
  Reg2: UInt8 = 0;
  Reg3: UInt8 = 0;
{$J-}
var
  DataElement: packed record Bytes: array [1 .. 4] of Byte end;
  Data: UInt32 absolute DataElement;
  RawByte: AnsiString;
  Position: Integer;
begin
  Position := Pos(LeftStr(ESP_READ_REG_ACK, 5), Frame);
  RawByte := LeftStr(Frame, Length(Frame) - Position + 1);
  if (Length(RawByte) >= Length(ESP_READ_REG_ACK)) then
  begin
    Data := PESPReadRegAck(@RawByte[1])^.RegValue;
    case CurrentAddress of
      $3FF00050:
        begin
          APMACStr := '';
          STAMACStr := '';
          Reg3 := DataElement.Bytes[4];
        end;
      $3FF00054:
        begin
          Reg1 := DataElement.Bytes[2];
          Reg2 := DataElement.Bytes[1];
          APMACStr := '1A-FE-34-' + IntToHex(Reg1, 2) + '-' + IntToHex(Reg2, 2)
            + '-' + IntToHex(Reg3, 2);
          STAMACStr := '18-FE-34-' + IntToHex(Reg1, 2) + '-' + IntToHex(Reg2, 2)
            + '-' + IntToHex(Reg3, 2);
        end;
      $3FF00058:
        begin
        end;
      $3FF0005C:
        begin
        end;
    end;
    // MemoOutput.Lines.Add(IntToHex(PESPReadRegAck(@RawByte[1])^.RegValue, 8));
  end;
end;

function TFormMain.GetUnicodeHex(const Str: AnsiString): string;
var
  I, Len: Integer;
  Temp: string;
begin
  Len := Length(Str);
  for I := 1 to Len do
  begin
    Temp := Temp + IntToHex(Ord(Str[I]), 2) + ' ';
  end;
  Result := Temp;
end;

function TFormMain.GetUnixString(const Str: AnsiString): AnsiString;
var
  I: Integer;
  Temp: AnsiString;
begin
  Temp := Str;
  ReplaceStr(Temp, #10, #13);
  ReplaceStr(Temp, #13#13, #13);
  Result := Temp;
end;

function TFormMain.GetXorCheck(const Str: AnsiString): UInt8;
var
  I: Integer;
  Temp: UInt8;
begin
  Temp := $EF;
  for I := 1 to Length(Str) do
  begin
    Temp := Temp xor Ord(Str[I]);
  end;
  Result := Temp;
end;

procedure TFormMain.LabelIntroductionClick(Sender: TObject);
begin
  TabSheetIntroduction.Show;
end;

procedure TFormMain.LoadSettings;
  procedure InitNote;
{$J+}
  const
    HaveShowed: Boolean = False;
{$J-}
  begin

    if (Not HaveShowed) then
    begin
      HaveShowed := True;
      TThread.CreateAnonymousThread(
        procedure
        const
          MAGIC_TIP = 'MAGIC_TIP_THIS_USER';
        var
          RespData: TStringStream;
          NoteStr: String;
        begin
          RespData := TStringStream.Create('', TEncoding.GetEncoding(65001));
          try
            try
              IdHTTPNote.Get
                ('http://www.vowstar.com/lambdadriver/2014/nodemcu/?version=20141205',
                RespData);
              NoteStr := RespData.DataString;
              if (Pos(MAGIC_TIP, NoteStr) <> 0) then
              begin
                NoteStr := ReplaceStr(NoteStr, MAGIC_TIP, '');
                TThread.Synchronize(nil,
                  procedure
                  begin
                    ShowMessage(NoteStr);
                  end);
              end
              else if (Length(NoteStr) > 10) then
              begin
                TThread.Synchronize(nil,
                  procedure
                  begin
                    RichEditNote.Text := NoteStr;
                  end);
              end;
            except
            end;
          finally
            FreeAndNil(RespData);
          end;
        end).Start;
    end;
  end;
  procedure InitRichEdit;
  var
    mask: Word;
  begin
    mask := SendMessage(RichEditNote.Handle, EM_GETEVENTMASK, 0, 0);
    SendMessage(RichEditNote.Handle, EM_SETEVENTMASK, 0, mask or ENM_LINK);
    SendMessage(RichEditNote.Handle, EM_AUTOURLDETECT, Integer(True), 0);
    RichEditNote.Font.Color := clWhite;
  end;

begin
  FrameConfigLine1.FilePath := 'INTERNAL://NODEMCU';
  FrameConfigLine1.Offset := '0x00000';
  FrameConfigLine1.CheckBoxEnable.Checked := True;

  // FrameConfigLine2.FilePath := 'INTERNAL://FLASH';
  // FrameConfigLine2.Offset := '0x00000';
  // FrameConfigLine2.CheckBoxEnable.Checked := True;
  // FrameConfigLine3.FilePath := 'INTERNAL://IROM';
  // FrameConfigLine3.Offset := '0x40000';
  // FrameConfigLine3.CheckBoxEnable.Checked := True;
  // FrameConfigLine4.FilePath := 'INTERNAL://DEFAULT';
  // FrameConfigLine4.Offset := '0x7C000';
  // FrameConfigLine4.CheckBoxEnable.Checked := True;

  InitRichEdit;
  InitNote;
end;

procedure TFormMain.ActionBurnExecute(Sender: TObject);
begin
  if (not CommMain.PortOpen) then
  begin
    if ComboBoxSerialPortA.Text = '' then
    begin
      MemoOutput.Lines.Add('Error:Serial port not exist.');
    end
    else
    begin
      CommMain.CommName := ComboBoxSerialPortA.Text;
      CommMain.BaudRate := 115200; // 42s To Flash
      // CommMain.BaudRate := 576000; // 29s To Flash
      // CommMain.BaudRate := 960000; // 27s To Flash
      CommMain.Parity := None;
      CommMain.ByteSize := _8;
      CommMain.StopBits := _1;
      CommMain.InputLen := 255;
      CommMain.StartComm;
      if (CommMain.PortOpen) then
      begin
        MemoOutput.Lines.Add('Note:Serial port connected.');
        BurnOK := False;
        RunState := StateHandshake;
        TimerStateMachine.Enabled := True;
        ChangeIconWait;
        MemoOutput.Lines.Add('Note:Begin find ESP8266.');
        ButtonBurn.Caption := 'Stop(&S)';
        // Set RTS to LOW
        CommMain.RtsControl := TRtsControl.RtsEnable;
        // Set DTR to LOW
        CommMain.DtrControl := TDtrControl.DtrEnable;
        Sleep(100);
        Application.ProcessMessages;
        // Set DTR to HIGH, Do Reset
        // CommMain.DtrControl := TDtrControl.DtrDisable;
      end
      else
      begin
        MemoOutput.Lines.Add
          ('Error:Serial port connect failed, please check it.');
      end;
    end;
  end
  else
  begin
    CommMain.StopComm;
    if (not(CommMain.PortOpen)) then
    begin
      MemoOutput.Lines.Add('Note:Serial port disconnected.');
      BurnOK := True;
      RunState := StateFinished;
      TimerStateMachine.Enabled := False;
      if (Sender = ActionBurn) then
      begin
        MemoOutput.Lines.Add('Warning:Serial port closed by user.');
        ChangeIconFail;
      end;
      // Set RTS to HIGH
      // CommMain.RtsControl := TRtsControl.RtsDisable;
      // Set RTS to LOW
      CommMain.RtsControl := TRtsControl.RtsEnable;
      // Set DTR to LOW
      CommMain.DtrControl := TDtrControl.DtrEnable;
      ButtonBurn.Caption := 'Flash(&F)';
    end
    else
    begin
      MemoOutput.Lines.Add
        ('Error:Serial port disconnect failed, please reopen this program.');
    end;
  end;
end;

procedure TFormMain.TimerCodeTimer(Sender: TObject);
const
{$J+}
  ColorIndex: Integer = 0;
  TextIndex: Integer = 0;
{$J-}
var
  CurrentColor: TColor;
begin
  ColorIndex := ColorIndex + (255 div 30);
  if (ColorIndex >= 255) then
  begin
    ColorIndex := 0;
    TextIndex := TextIndex + 1;
    case TextIndex of
      0:
        LabelIntroduction.Caption := 'require("nodemcu")';
      1:
        LabelIntroduction.Caption := '';
      2:
        LabelIntroduction.Caption := 'require("wifi")';
      3:
        LabelIntroduction.Caption := '';
      4:
        LabelIntroduction.Caption := 'require("gpio")';
      5:
        LabelIntroduction.Caption := '';
      6:
        LabelIntroduction.Caption := 'connect.world()';
      7:
        LabelIntroduction.Caption := '';
    else
      TextIndex := 0;
    end;
  end;
  CurrentColor := Round(128 - Abs(128 - ColorIndex));
  LabelIntroduction.Font.Color := RGB(CurrentColor, CurrentColor, CurrentColor);
end;

procedure TFormMain.TimerFindPortsTimer(Sender: TObject);
var
  SerialPorts: TStringList;

begin
  SerialPorts := TStringList.Create;
  EnumComPorts(SerialPorts);
  if (SerialPorts.Count <> ComboBoxSerialPortA.Items.Count) then
  begin
    ComboBoxSerialPortA.Items.Assign(SerialPorts);
    MemoOutput.Lines.Add('Note:Detect serial port changed.');
    if (SerialPorts.Count >= 1) then
    begin
      ComboBoxSerialPortA.ItemIndex := ComboBoxSerialPortA.Items.Count - 1;
      MemoOutput.Lines.Add('Note:Auto MAP serial port.' + 'Port-->' +
        ComboBoxSerialPortA.Text + #13#10);
    end;
  end;
  SerialPorts.Free;
end;

procedure TFormMain.TimerStateMachineTimer(Sender: TObject);
const
{$J+}
  HandshakeCount: Integer = 0;
{$J-}
  // 高精度的延时，精确到Ms , 100ms以内采用，或要求误差极小
  // 删除Application.ProcessMessages 影响精度
  procedure DelayMsEx(Ms: Double);
  var
    iFreq, iStartCounter, iEndCounter: Int64;
  begin
    QueryPerformanceFrequency(iFreq);
    QueryPerformanceCounter(iStartCounter);
    repeat
      QueryPerformanceCounter(iEndCounter);
      // Application.ProcessMessages;
    until ((iEndCounter - iStartCounter) >= Round(Ms * iFreq / 1000));
  end;

var
  I: Integer;

begin
{$DEFINE TRIODEMODE}
  if (not BurnOK) then
    case (RunState) of
      StateHandshake:
        begin
          Inc(HandshakeCount);
          if (HandshakeCount >= MaxInt) then
            HandshakeCount := 0;
{$IFDEF CAPMODE}
          if (HandshakeCount mod 8 = 0) then
          begin
            // Set RTS to HIGH
            CommMain.RtsControl := TRtsControl.RtsDisable;
            // Application.ProcessMessages;
            // Set DTR to HIGH
            CommMain.DtrControl := TDtrControl.DtrDisable;
            Application.ProcessMessages;
            Sleep(50);
            // Set DTR to LOW, RESET MCU
            CommMain.DtrControl := TDtrControl.DtrEnable;
            // Application.ProcessMessages;
            // Sleep 9~12 ms
            // Sleep(12);

            for I := 1 to 10 do
            begin
              DelayMsEx(1);
              CommMain.RtsControl := TRtsControl.RtsEnable;
              DelayMsEx(1);
              CommMain.RtsControl := TRtsControl.RtsDisable;
            end;
            // Set RTS to LOW, GPIO0 LOW
            CommMain.RtsControl := TRtsControl.RtsEnable;
            Application.ProcessMessages;
            Sleep(50);
            // Set RTS to HIGH
            // CommMain.RtsControl := TRtsControl.RtsDisable;
            // Application.ProcessMessages;
            // Set DTR to HIGH
            // CommMain.DtrControl := TDtrControl.DtrDisable;
          end;
{$ENDIF}
{$IFDEF TRIODEMODE}
          if (HandshakeCount mod 20 = 0) then
          begin
            // Set DTR, RTS to LOW
            CommMain.DtrControl := TDtrControl.DtrEnable;
            CommMain.RtsControl := TRtsControl.RtsEnable;

            DelayMsEx(10);
            // Set DTR, HIGH -> RST LOW
            CommMain.DtrControl := TDtrControl.DtrDisable;
            DelayMsEx(10);
            // Set RTS, HIGH -> RST HIGH
            CommMain.RtsControl := TRtsControl.RtsDisable;
            // Set DTR, LOW  -> GPIO LOW
            CommMain.DtrControl := TDtrControl.DtrEnable;

            Sleep(50);
          end;
{$ENDIF}
          SendString(ESP_HANDSHAKE);
        end;
      StateBurn:
        begin
          if (not IsThreadStarted) then
          begin
            TThread.CreateAnonymousThread(FlashImage).Start;
          end;
        end;
      StateRun:
        begin
          SendString(ESP_RUN);
          RunState := StateFinished;
        end;
      StateFinished:
        begin
          BurnOK := True;
        end;
    else
      BurnOK := True;
    end
  else
  begin
    TimerStateMachine.Enabled := False;
    RunState := StateFinished;
  end;
end;

procedure TFormMain.UpdateQRCode(QRText: String);
var
  QRCode: TDelphiZXingQRCode;
  Row, Column: Integer;
  QRCodeBitmap: TBitmap;
begin
  QRCodeBitmap := TBitmap.Create;
  QRCode := TDelphiZXingQRCode.Create;
  try
    QRCode.Data := QRText;
    QRCode.Encoding := TQRCodeEncoding(qrAuto);
    QRCode.QuietZone := 4;
    QRCodeBitmap.SetSize(QRCode.Rows, QRCode.Columns);
    for Row := 0 to QRCode.Rows - 1 do
    begin
      for Column := 0 to QRCode.Columns - 1 do
      begin
        if (QRCode.IsBlack[Row, Column]) then
        begin
          QRCodeBitmap.Canvas.Pixels[Column, Row] := clBlack;
        end
        else
        begin
          QRCodeBitmap.Canvas.Pixels[Column, Row] := clWhite;
        end;
      end;
    end;
    ImageQRCode.Picture.Bitmap := QRCodeBitmap;
  finally
    QRCode.Free;
    QRCodeBitmap.Free;
  end;
end;

procedure TFormMain.WriteMACFile(const MACStr, FileName: string);
var
  MACFile: TextFile;
begin
  if not FileExists(FileName) then
  begin
    Assignfile(MACFile, FileName);
    rewrite(MACFile);
    Closefile(MACFile);
  end;
  Assignfile(MACFile, FileName);
  Append(MACFile);
  Writeln(MACFile, MACStr);
  Closefile(MACFile);
end;

procedure TFormMain.ReceiveData(Sender: TObject; Buffer: PAnsiChar;
BufferLength: Word);
var
  I: Integer;
begin
  for I := 1 to BufferLength do
  begin

    begin
      SerailBufferA := SerailBufferA + (PAnsiChar(Buffer)^);
    end;
    if (I <> BufferLength) then
      Inc(Buffer);
  end;

  if (Length(SerailBufferA) > 0) then
  begin
    if (Pos(ESP_PROTOCOL_ACK, SerailBufferA) <> 0) then
    begin
      // MemoOutput.Lines.Add('Note:串行端口接收到数据.');
      // MemoOutput.Lines.Add('RECV:' + GetUnicodeHex(SerailBufferA));
      if (Pos(ESP_HANDSHAKE_ACK, SerailBufferA) <> 0) then
      begin
        MemoOutput.Lines.Add('Note:ESP8266 ACK success.');
        RunState := StateBurn;
      end;
      if (Pos(LeftStr(ESP_SET_BASE_ADDRESS_ACK, 5), SerailBufferA) <> 0) then
      begin
        MemoOutput.Lines.Add('Note:Set base address success.');
        LastOperationSuccess := True;
      end;
      if (Pos(LeftStr(ESP_SEND_DATA_ACK, 5), SerailBufferA) <> 0) then
      begin
        MemoOutput.Lines.Add('Note:Program flash success.');
        LastOperationSuccess := True;
      end;
      if (Pos(LeftStr(ESP_RUN_ACK, 5), SerailBufferA) <> 0) then
      begin
        MemoOutput.Lines.Add('Note:Program success, run user code.');
        RunState := StateFinished;
        ChangeIconSuccess;
        if (CommMain.PortOpen) then
          ButtonBurn.OnClick(Self);
      end;

      // MemoOutput.Lines.Add
      // ('Left:' + GetUnicodeHex(LeftStr(ESP_READ_REG_ACK, 5)));

      if (Pos(LeftStr(ESP_READ_REG_ACK, 5), SerailBufferA) <> 0) then
      begin
        // MemoOutput.Lines.Add('Note:读芯片寄存器成功.');
        GetRegValue(SerailBufferA);
        LastOperationSuccess := True;
      end;
      SerailBufferA := '';
    end;
  end;
end;

end.
