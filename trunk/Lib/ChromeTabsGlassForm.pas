unit ChromeTabsGlassForm;

// The contents of this file are subject to the Mozilla Public License
// Version 1.1 (the "License"); you may not use this file except in compliance
// with the License. You may obtain a copy of the License at http://www.mozilla.org/MPL/
//
// Alternatively, you may redistribute this library, use and/or modify it under the terms of the
// GNU Lesser General Public License as published by the Free Software Foundation;
// either version 2.1 of the License, or (at your option) any later version.
// You may obtain a copy of the LGPL at http://www.gnu.org/copyleft/.
//
// Software distributed under the License is distributed on an "AS IS" basis,
// WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the
// specific language governing rights and limitations under the License.
//
// The original code is ChromeTabs.pas, released December 2012.
//
// The initial developer of the original code is Easy-IP AS (Oslo, Norway, www.easy-ip.net),
// written by Paul Spencer Thornton (paul.thornton@easy-ip.net, www.easy-ip.net).
//
// Portions created by Easy-IP AS are Copyright
// (C) 2012 Easy-IP AS. All Rights Reserved.
//
// ----------------------------------------------------------------------------
//
// Based on code provided by Chris Rolliston.
// http://delphihaven.wordpress.com/2010/04/22/setting-up-a-custom-title-bar-reprise/

interface

uses
  Windows, Messages, SysUtils, Classes, Forms, Controls,

  ChromeTabs;

type
  TChromeTabsGlassForm = class(TForm)
  private
    FDwmBorderIconsRect: TRect;
    FWndFrameSize: Integer;
    FChromeTabs: TChromeTabs;
    FChromeTabsWindowedTopOffset: Integer;
    FChromeTabsMaxmizedTopOffset: Integer;
    FChromeTabsMaximizedRightOffset: Integer;
    FChromeTabsWindowedRightOffset: Integer;

    procedure RecalcGlassFrameBounds(UpdateFrame: Boolean = TRUE);
    procedure SetChromeTabs(const Value: TChromeTabs);
    function UseCustomFrame: Boolean;
    procedure UpdateChromeTabPosition;
    procedure SetChromeTabsMaximizedRightOffset(const Value: Integer);
    procedure SetChromeTabsMaxmizedTopOffset(const Value: Integer);
    procedure SetChromeTabsWindowedRightOffset(const Value: Integer);
    procedure SetChromeTabsWindowedTopOffset(const Value: Integer);
  protected
    // Overrides
    procedure AdjustClientRect(var Rect: TRect); override;
    procedure PaintWindow(DC: HDC); override;
    procedure Resize; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;

    // Messages
    procedure WMNCCalcSize(var Message: TWMNCCalcSize); message WM_NCCALCSIZE;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMNCRButtonUp(var Message: TWMNCRButtonUp); message WM_NCRBUTTONUP;
    procedure WMWindowPosChanging(var Message: TWMWindowPosChanging); message WM_WINDOWPOSCHANGING;
    procedure WMWindowPosChanged(var Message: TWMWindowPosChanged); message WM_WINDOWPOSCHANGED;
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;

    property ChromeTabs: TChromeTabs read FChromeTabs write SetChromeTabs;
    property ChromeTabsWindowedTopOffset: Integer read FChromeTabsWindowedTopOffset write SetChromeTabsWindowedTopOffset;
    property ChromeTabsMaxmizedTopOffset: Integer read FChromeTabsMaxmizedTopOffset write SetChromeTabsMaxmizedTopOffset;
    property ChromeTabsMaximizedRightOffset: Integer read FChromeTabsMaximizedRightOffset write SetChromeTabsMaximizedRightOffset;
    property ChromeTabsWindowedRightOffset: Integer read FChromeTabsWindowedRightOffset write SetChromeTabsWindowedRightOffset;
  end;

implementation

uses
  CommCtrl, DwmApi;

function GetDwmBorderIconsRect(Form: TForm): TRect;
begin
  if Win32MajorVersion >= 6 then
  begin
    if DwmGetWindowAttribute(Form.Handle,
                             DWMWA_CAPTION_BUTTON_BOUNDS,
                             @Result,
                             SizeOf(Result)) <> S_OK then
                             SetRectEmpty(Result);
  end
  else
    SetRectEmpty(Result);
end;

procedure ShowSystemMenu(Form: TForm; const Message: TWMNCRButtonUp);
var
  Cmd: WPARAM;
  Menu: HMENU;

  procedure UpdateItem(ID: UINT; Enable: Boolean; MakeDefaultIfEnabled: Boolean = FALSE);
  const
    Flags: array [Boolean] of UINT = (MF_GRAYED, MF_ENABLED);
  begin
    EnableMenuItem(Menu, ID, MF_BYCOMMAND or Flags[Enable]);

    if MakeDefaultIfEnabled and Enable then
      SetMenuDefaultItem(Menu, ID, MF_BYCOMMAND);
  end;

begin
  Menu := GetSystemMenu(Form.Handle, FALSE);

  if Form.BorderStyle in [bsSingle, bsSizeable, bsToolWindow, bsSizeToolWin]
  then
  begin
    SetMenuDefaultItem(Menu, UINT(-1), 0);

    UpdateItem(SC_RESTORE, Form.WindowState <> wsNormal, TRUE);

    UpdateItem(SC_MOVE, Form.WindowState <> wsMaximized);

    UpdateItem(SC_SIZE, (Form.WindowState <> wsMaximized) and
      (Form.BorderStyle in [bsSizeable, bsSizeToolWin]));

    UpdateItem(SC_MINIMIZE, (biMinimize in Form.BorderIcons) and
      (Form.BorderStyle in [bsSingle, bsSizeable]));

    UpdateItem(SC_MAXIMIZE, (biMaximize in Form.BorderIcons) and
      (Form.BorderStyle in [bsSingle, bsSizeable]) and
      (Form.WindowState <> wsMaximized), TRUE);
  end;

  if Message.HitTest = HTSYSMENU then
    SetMenuDefaultItem(Menu, SC_CLOSE, MF_BYCOMMAND);

  Cmd := WPARAM(TrackPopupMenu(Menu,
                               TPM_RETURNCMD or GetSystemMetrics(SM_MENUDROPALIGNMENT),
                               Message.XCursor,
                               Message.YCursor,
                               0,
                               Form.Handle, nil));

  PostMessage(Form.Handle, WM_SYSCOMMAND, Cmd, 0)
end;


{ TChromeTabsGlassForm }

procedure TChromeTabsGlassForm.AdjustClientRect(var Rect: TRect);
begin
  inherited;

  if UseCustomFrame then
    Inc(Rect.Top, GlassFrame.Top);
end;

procedure TChromeTabsGlassForm.PaintWindow(DC: HDC);
var
  R: TRect;
begin
  if UseCustomFrame then
  begin
    R := GetClientRect;

    with GlassFrame do
      ExcludeClipRect(DC,
                      GlassFrame.Left,
                      GlassFrame.Top,
                      R.Right - GlassFrame.Right,
                      R.Bottom - GlassFrame.Bottom);
  end;

  inherited;
end;

procedure TChromeTabsGlassForm.RecalcGlassFrameBounds(UpdateFrame: Boolean);
var
  R: TRect;
begin
  SetRectEmpty(R);

  AdjustWindowRectEx(R,
                     GetWindowLong(Handle, GWL_STYLE),
                     FALSE,
                     GetWindowLong(Handle, GWL_EXSTYLE));

  FWndFrameSize := R.Right;

  if UpdateFrame then
    SetWindowPos(Handle, 0, Left, Top, Width, Height, SWP_FRAMECHANGED);
end;

procedure TChromeTabsGlassForm.Resize;
begin
  if UseCustomFrame then
  begin
    FDwmBorderIconsRect := GetDwmBorderIconsRect(Self);

    UpdateChromeTabPosition;

    FChromeTabs.InvalidateAllControls;
  end;

  inherited;
end;

procedure TChromeTabsGlassForm.WMNCCalcSize(var Message: TWMNCCalcSize);
begin
  if UseCustomFrame then
  begin
    Inc(Message.CalcSize_Params.rgrc[0].Left, FWndFrameSize);
    Dec(Message.CalcSize_Params.rgrc[0].Right, FWndFrameSize);
    Dec(Message.CalcSize_Params.rgrc[0].Bottom, FWndFrameSize);
  end
  else
    inherited;
end;

procedure TChromeTabsGlassForm.WMNCHitTest(var Message: TWMNCHitTest);
var
  ClientPos: TPoint;
  IconRect: TRect;
begin
  inherited;

  if UseCustomFrame then
  begin
    if Message.Result in [HTMINBUTTON, HTMAXBUTTON, HTCLOSE] then
    begin
      Message.Result := HTCAPTION; // slay ghost btns when running on Win64
    end
    else
    begin
      ClientPos := ScreenToClient(Point(Message.XPos, Message.YPos));

      if ClientPos.Y <= GlassFrame.Top then
      begin
        if (ClientPos.X < IconRect.Right) and
           ((WindowState = wsMaximized) or
            ((ClientPos.Y >= IconRect.Top) and
             (ClientPos.Y < IconRect.Bottom))) then
          Message.Result := HTSYSMENU else
        if ClientPos.Y < FWndFrameSize then
          Message.Result := HTTOP
        else
          Message.Result := HTCAPTION;
      end;
    end;
  end;
end;

procedure TChromeTabsGlassForm.WMNCRButtonUp(var Message: TWMNCRButtonUp);
begin
  if (not UseCustomFrame) or
     (not (biSystemMenu in BorderIcons)) then
    inherited
  else
  begin
    if Message.HitTest in [HTCAPTION, HTSYSMENU] then
      ShowSystemMenu(Self, Message)
    else
      inherited;
  end;
end;

procedure TChromeTabsGlassForm.WMWindowPosChanging(var Message: TWMWindowPosChanging);
const
  SWP_STATECHANGED = $8000;
begin
  if UseCustomFrame then
  begin
    if Message.WindowPos.flags and SWP_STATECHANGED = SWP_STATECHANGED then
      Invalidate;
  end;

  inherited;

  if (UseCustomFrame) and
     (Message.WindowPos.flags and SWP_FRAMECHANGED <> 0) and
     (Message.WindowPos.flags <> SWP_FRAMECHANGED) then
    RecalcGlassFrameBounds(FALSE);
end;

procedure TChromeTabsGlassForm.WMWindowPosChanged(var Message: TWMWindowPosChanged);
begin
  inherited;

  if (UseCustomFrame) and
     (Message.WindowPos.flags and SWP_FRAMECHANGED <> 0) then
    Realign;
end;

procedure TChromeTabsGlassForm.WndProc(var Message: TMessage);
begin
  if not UseCustomFrame or not HandleAllocated or
    not DwmDefWindowProc(Handle, Message.Msg, Message.WParam, Message.LParam,
    Message.Result) then
    inherited;
end;

procedure TChromeTabsGlassForm.SetChromeTabs(const Value: TChromeTabs);
begin
  FChromeTabs := Value;

  if not (csDestroying in ComponentState) then
  begin
    if FChromeTabs <> nil then
    begin
      FChromeTabs.Align := alNone;
    end;

    GlassFrame.Enabled := UseCustomFrame;

    RecalcGlassFrameBounds(TRUE);

    Invalidate;
  end;
end;

procedure TChromeTabsGlassForm.SetChromeTabsMaximizedRightOffset(
  const Value: Integer);
begin
  FChromeTabsMaximizedRightOffset := Value;

  Invalidate;
end;

procedure TChromeTabsGlassForm.SetChromeTabsMaxmizedTopOffset(
  const Value: Integer);
begin
  FChromeTabsMaxmizedTopOffset := Value;

  Invalidate;
end;

procedure TChromeTabsGlassForm.SetChromeTabsWindowedRightOffset(
  const Value: Integer);
begin
  FChromeTabsWindowedRightOffset := Value;

  Invalidate;
end;

procedure TChromeTabsGlassForm.SetChromeTabsWindowedTopOffset(
  const Value: Integer);
begin
  FChromeTabsWindowedTopOffset := Value;

  Invalidate;
end;

procedure TChromeTabsGlassForm.UpdateChromeTabPosition;
var
  TopOffset, RightOffset: Integer;
begin
  if UseCustomFrame then
  begin
    if WindowState = wsMaximized then
    begin
      TopOffset := FChromeTabsMaxmizedTopOffset;
      RightOffset := FChromeTabsMaximizedRightOffset
    end
    else
    begin
      TopOffset := FChromeTabsWindowedTopOffset;
      RightOffset := FChromeTabsWindowedRightOffset;
    end;

    GlassFrame.Top := FChromeTabs.Height + TopOffset;

    FChromeTabs.Top := TopOffset;
    FChromeTabs.Left := 0;
    FChromeTabs.Width := Width - (FDwmBorderIconsRect.Right - FDwmBorderIconsRect.Left) - RightOffset;

    RecalcGlassFrameBounds(FALSE);
  end;
end;

function TChromeTabsGlassForm.UseCustomFrame: Boolean;
begin
  Result := FChromeTabs <> nil;
end;

constructor TChromeTabsGlassForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  // Set the defaults
  FChromeTabsWindowedTopOffset := 12;
  FChromeTabsMaxmizedTopOffset := 4;
  FChromeTabsWindowedRightOffset := 20;
  FChromeTabsMaximizedRightOffset := 35;
end;

procedure TChromeTabsGlassForm.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);

  if Operation = opRemove then
  begin
    if AComponent = FChromeTabs then
      SetChromeTabs(nil);
  end;
end;

end.
