unit cocinasync.tests.async;

interface

uses
  DUnitX.TestFramework, cocinasync.async;

type

  [TestFixture]
  TestTAsync = class(TObject)
  strict private
  public
    [Test]
    procedure DoLater;
    [Test]
    procedure OnDo;
    [Test]
    procedure DoEvery;
    [Test]
    procedure AfterDo;
    [Test]
    procedure EarlyFree;
    // Test with TestCase Atribute to supply parameters.
  end;

implementation

uses System.SysUtils, System.DateUtils, SyncObjs;

procedure TestTAsync.OnDo;
var
  bDo, bDone : boolean;
  iOnCnt, iDoCnt : integer;
begin
  iOnCnt := 0;
  iDoCnt := 0;
  bDo := False;
  bDone := False;
  Async.OnDo(
    function : boolean
    begin
      TInterlocked.Increment(iOnCnt);
      Result := bDo;
    end,
    procedure
    begin
      TInterlocked.Increment(iDoCnt);
      bDone := True;
    end,
    1000,nil,False,False
  );
  Sleep(10);
  if bDone then
  begin
    Assert.Fail('Did not wait until told to continue. OnCnt: '+iOnCnt.ToString+'  DoCnt: '+iDoCnt.ToString);
    exit;
  end;
  bDo := True;
  Sleep(1010);
  if iOnCnt = 0 then
    Assert.Fail('On Never Fired.');
  if iDoCnt > 1 then
    Assert.Fail('Do fired more than once.');
  Assert.AreEqual(True, bDone);
end;

procedure TestTAsync.AfterDo;
var
  bDone : boolean;
begin
  bDone := False;
  Async.AfterDo(100,
    procedure
    begin
      bDone := True;
    end
  );
  Sleep(210);
  Assert.AreEqual(True, bDone);
end;

procedure TestTAsync.DoEvery;
var
  iCnt : integer;
begin
  iCnt := 1;
  Async.DoEvery(10,
    function : boolean
    begin
      inc(iCnt);
      if iCnt >= 10 then
        Result := False
      else
        Result := True;
    end
  );
  Sleep(1000);
  Assert.AreEqual(10, iCnt);
end;

procedure TestTAsync.DoLater;
var
  bDone : boolean;
begin
  bDone := False;
  Async.DoLater(
    procedure
    begin
      bDone := True;
    end
  );
  Sleep(100);
  Assert.AreEqual(True, bDone);
end;

procedure TestTAsync.EarlyFree;
var
  async : TAsync;
  iCnt : integer;
  DoLaterProc : TProc;
  DoAfterProc : TProc;
begin
  try
    iCnt := 0;
    async := TAsync.Create;
    try
      async.DoEvery(10,
        function : boolean
        begin
          TInterlocked.Increment(iCnt);
        end
      );

      DoAfterProc :=
        procedure
        begin
          async.AfterDo(10, DoAfterPRoc);
        end;
      DoAfterProc();

      DoLaterProc :=
        procedure
        begin
          async.DoLater(DoLaterProc);
        end;
      DoLaterProc();

      async.DoEvery(10,
        function : boolean
        begin
          Result := True;
        end
      );
      sleep(100);
    finally
      async.Free;
    end;
  except
    on E : Exception do
    begin
      Assert.Fail(E.Message);
      exit;
    end;
  end;
  if iCnt > 0 then
    Assert.Pass
  else
    Assert.Fail('DoEvery Did not run');
end;

initialization
  TDUnitX.RegisterTestFixture(TestTAsync);
end.

