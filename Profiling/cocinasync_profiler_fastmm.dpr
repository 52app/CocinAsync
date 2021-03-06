program cocinasync_profiler_fastmm;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  FastMM4,
  System.SysUtils,
  System.Classes,
  cocinasync.global,
  cocinasync.async,
  cocinasync.jobs,
  cocinasync.profiler in 'cocinasync.profiler.pas';


var
  logproc : TLogProc;
  cs : TConsole;
  bAppFinished : boolean;
  sFilename : string;
  slProfile : TStringList;
  iRunCount : integer;
begin
  try
    cs := TConsole.Create;
    try
      slProfile := TStringList.Create;
      try
        sFilename := ExtractFilePath(ParamStr(0))+'profile_fastmm.log';
        if FileExists(sFilename) then
          DeleteFile(sFilename);

        if ParamCount >= 2 then
          iRunCount := StrToIntDef(ParamStr(1),3)
        else
          iRunCount := 3;

        logproc :=
          procedure(const msg : string)
          begin
            TAsync.SynchronizeIfInThread(
              procedure
              begin
                slProfile.Add(msg);
                WriteLn(msg);
                if msg.StartsWith('--') then
                  slProfile.SaveToFile(sFilename);
              end
            );
          end;

        bAppFinished := False;

        Jobs.Queue(
          procedure
          begin
            TProfiles.DoTest(iRunCount, logproc);
            bAppFinished := True;
          end
        );

        cs.ApplicationLoop(
          function : boolean
          begin
            Result := not bAppFinished;
          end
        );

        logproc('');
        logproc('');
        logproc('Finished, Press Enter to exit.');
        slProfile.SaveToFile(sFilename);
        Readln;
      finally
        slProfile.Free;
      end;
    finally
      cs.Free;
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

end.
