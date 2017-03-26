unit cocinasync.collections;

interface

uses System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Defaults,
  System.TypInfo;

type
  TInterlockedHelper = class helper for TInterlocked
  public
    class function CompareExchange(var Target: Pointer; Value: Pointer; Comparand: Pointer; out Succeeded: Boolean): Pointer;
  end;

  TQueue<T> = class(TObject)
  strict private
    type
      PQueuePointer = ^TQueuePointer;
      TQueuePointer = record
        FData : T;
        FNext : Pointer;
      end;
  strict private
    FFirst : PQueuePointer;
    procedure Enqueue(const Value: T; NewItem : PQueuePointer; const Wait : TSpinWait); overload;// inline;
  public
    constructor Create; reintroduce; virtual;
    destructor Destroy; override;

    procedure Enqueue(const Value: T); overload; //inline;
    function Dequeue: T; overload;// inline;
    procedure Clear;
  end;

  TStack<T> = class(TObject)
  strict private
    type
      PStackPointer = ^TStackPointer;
      TStackPointer = record
        FData : T;
        FPrior : Pointer;
      end;
  strict private
    FTop : Pointer;
    FFirst : Pointer;
    function Pop(const wait : TSpinWait) : T; overload; inline;
  public
    constructor Create; reintroduce; virtual;
    destructor Destroy; override;

    procedure Push(const Value: T); inline;
    function Pop: T; overload; inline;
    function Peek: T; inline;
    procedure Clear;
  end;

  THash<K,V> = class(TObject)
  strict private
    type
    PItem = ^TItem;
    TItem = record
      Key: K;
      Value: V;
      Next: Pointer;
    end;
    TItemArray = TArray<Pointer>;
  strict private
    FMemSize: Cardinal;
    FSizeMask : Cardinal;
    FItems: TItemArray;
    FComparer : IEqualityComparer<K>;
    FKeyType: PTypeInfo;
    procedure GetMapPointer(Key: K; HashIdx : integer; var Prior, Current : PItem; var Depth : Integer);
    function GetMap(Key: K): V;
    procedure SetMap(Key: K; const Value: V; NewItem : PItem; const wait : TSpinWait); overload; //inline;
    procedure SetMap(Key: K; const Value: V); overload;
    function GetHas(Key: K): boolean;
    function GetHashIndex(Key : K) : Integer; //inline;
    function CalcDepth(item: PItem): integer; //inline;
  public
    type
      TDepth = record
        EmptyCnt : Cardinal;
        MaxDepth : Cardinal;
        Average  : Cardinal;
        AvgFilled : Cardinal;
        Size : Cardinal;
      end;
  public
    constructor Create(EstimatedItemCount : Integer = 1024); reintroduce; virtual;
    destructor Destroy; override;

    function DebugDepth : TDepth;
    procedure Delete(const Key : K);
    procedure AddOrSetValue(const Key : K; const Value : V);
    property Has[Key : K] : boolean read GetHas;
    property Map[Key : K] : V read GetMap write SetMap; default;
  end;

implementation

uses Math;

class function TInterlockedHelper.CompareExchange(var Target: Pointer; Value: Pointer; Comparand: Pointer; out Succeeded: Boolean): Pointer;
begin
  Result := AtomicCmpExchange(Target, Value, Comparand, Succeeded);
end;


{ TQueue<T> }

procedure TQueue<T>.Clear;
begin
  while FFirst^.FNext <> nil do
    Dequeue;
end;

constructor TQueue<T>.Create;
var
  p : PQueuePointer;
begin
  inherited Create;
  New(p);
  p^.FData := T(nil);
  p^.FNext := nil;
  FFirst := p;
end;

function TQueue<T>.Dequeue: T;
var
  p : PQueuePointer;
  sw : TSpinWait;
  bSuccess : boolean;
begin
  if FFirst^.FNext = nil then
  begin
    Exit(T(nil));
  end;
  sw.Reset;
  repeat
    p := FFirst^.FNext;
    TInterlocked.CompareExchange(FFirst^.FNext, p.FNext,p,bSuccess);
    if not bSuccess then
      sw.SpinCycle;
  until bSuccess;
  Result := p^.FData;
  Dispose(p);
end;

destructor TQueue<T>.Destroy;
begin
  Clear;
  Dispose(FFirst);
  inherited;
end;

procedure TQueue<T>.Enqueue(const Value: T; NewItem : PQueuePointer; const Wait: TSpinWait);
var
  pLast : PQueuePointer;
  sw : TSpinWait;
  bSuccess : boolean;
begin
  pLast := FFirst;
  while pLast^.FNext <> nil do
    pLast := pLast^.FNext;

  sw.Reset;
  TInterlocked.CompareExchange(pLast^.FNext,NewItem,nil,bSuccess);
  if not bSuccess then
  begin
    Enqueue(Value, NewItem, Wait);
    sw.SpinCycle;
  end;
end;

procedure TQueue<T>.Enqueue(const Value: T);
var
  p : PQueuePointer;
  sw : TSpinWait;
  bSuccess : boolean;
begin
  New(p);
  p^.FData := Value;
  p^.FNext := nil;

  sw.Reset;
  Enqueue(Value, p, sw);
end;

{ TStack<T> }

procedure TStack<T>.Clear;
var
  val : T;
  bAssigned : boolean;
begin
  while FTop <> FFirst do
    Pop;
end;

constructor TStack<T>.Create;
var
  p : PStackPointer;
begin
  inherited Create;
  New(p);
  p^.FData := T(nil);
  p^.FPrior := nil;
  FFirst := p;
  FTop := p;
end;

destructor TStack<T>.Destroy;
begin
  Clear;
  Dispose(PStackPointer(FFirst));
  inherited;
end;

function TStack<T>.Peek: T;
begin
  if FTop <> nil then
  begin
    Result := PStackPointer(FTop)^.FData;
  end else
    Result := T(nil);
end;

function TStack<T>.Pop(const wait : TSpinWait): T;
var
  p, pTop : PStackPointer;
  iCnt : integer;
  bSucceeded : boolean;
begin
  pTop := FTop;
  if (pTop <> nil) and (pTop <> FFirst) then
  begin
    p := PStackPointer(TInterlocked.CompareExchange(FTop,PStackPointer(pTop)^.FPrior, pTop,bSucceeded));
    if bSucceeded then
    begin
      Result := p^.FData;
      Dispose(PStackPointer(pTop));
    end else
    begin
      wait.SpinCycle;
      Result := Pop(wait);
    end;
  end else
    Result := T(nil);
end;

function TStack<T>.Pop: T;
var
  sw : TSpinWait;
begin
  sw.Reset;
  Result := Pop(sw);
end;

procedure TStack<T>.Push(const Value: T);
var
  ptop, p : PStackPointer;
  bSuccess : boolean;
  sw : TSpinWait;
begin
  New(p);
  p^.FData := Value;
  bSuccess := False;
  sw.Reset;
  repeat
    p.FPrior := FTop;
    TInterlocked.CompareExchange(FTop, p, p^.FPrior, bSuccess);
    if not bSuccess then
    begin
      sw.SpinCycle;
    end;
  until bSuccess;
end;

{ THash<K, V> }

procedure THash<K, V>.AddOrSetValue(const Key: K; const Value: V);
begin
  SetMap(Key, Value);
end;

constructor THash<K, V>.Create(EstimatedItemCount : Integer = 1024);
var
  i: Integer;
begin
  inherited Create;
  FMemSize := $FFFFFF;
  while (EstimatedItemCount < FMemSize) and (FMemSize > $F) do
    FMemSize := FMemSize shr 4;
  SetLength(FItems,FMemSize+1);
  FKeyType := TypeInfo(K);
  FComparer := TEqualityComparer<K>.Default;
  for i := Low(FItems) to High(FItems) do
    FItems[i] := nil;
end;

function THash<K, V>.CalcDepth(item : PItem) : integer;
begin
  Result := 1;
  while (item <> nil) and (item.Next <> nil) do
  begin
    inc(Result);
    item := item.Next;
  end;
end;

function THash<K, V>.DebugDepth: TDepth;
var
  i, iDepth : integer;
begin
  Result.EmptyCnt := 0;
  Result.MaxDepth := 0;
  Result.Average := 0;
  Result.AvgFilled := 0;
  Result.Size := FMemSize+1;
  for i := 0 to FMemSize do
  begin
    if FItems[i] <> nil then
    begin
      iDepth := CalcDepth(FItems[I]);
      Result.MaxDepth := Max(Result.MaxDepth, iDepth);
      inc(Result.Average,iDepth);
      inc(Result.AvgFilled, iDepth);
    end else
      Inc(Result.EmptyCnt);
  end;
  Result.Average := Result.Average div (FMemSize+1);
  if FMemSize >= Result.EmptyCnt then
    Result.AvgFilled := Result.AvgFilled div ((FMemSize+1) - Result.EmptyCnt)
  else
    Result.AvgFilled := Result.Average;
end;

procedure THash<K, V>.Delete(const Key: K);
begin
  SetMap(Key, V(nil));
end;

destructor THash<K, V>.Destroy;
var
  p, pNext : PItem;
  i: Integer;
begin
  for i := Low(FItems) to High(FItems) do
    if FItems[i] <> nil then
    begin
      p := PItem(PItem(FItems[i])^.Next);
      while p <> nil do
      begin
        pNext := p^.Next;
        p^.Value := V(nil);
        Dispose(PItem(p));
        p := pNext;
      end;
      Dispose(PItem(FItems[i]));
    end;
  inherited;
end;

function THash<K, V>.GetHas(Key: K): boolean;
var
  val : V;
begin
  val := GetMap(Key);
  Result := @val <> nil;
end;

function THash<K, V>.GetHashIndex(Key: K): Integer;
const Mask = not Integer($80000000);
begin
  result := (Mask and ((Mask and FComparer.GetHashCode(Key)) + 1)) and (FMemSize);
end;

function THash<K, V>.GetMap(Key: K): V;
var
  p, pPrior : PItem;
  iDepth : integer;
begin
  GetMapPointer(Key, GetHashIndex(Key), pPrior, p, iDepth);
  if p <> nil then
  begin
    Result := p.Value;
  end else
    Result := V(nil);
end;

procedure THash<K, V>.GetMapPointer(Key: K; HashIdx : integer; var Prior, Current : PItem; var Depth : Integer);
var
  p : PItem;
begin
  Depth := 0;
  Prior := nil;
  p := FItems[HashIdx];
  if p <> nil then
  begin
    if not FComparer.Equals(p.Key, Key) then
    begin
      repeat
        Prior := p;
        p := p.Next;
        inc(Depth);
      until (p = nil) or FComparer.Equals(p.Key, Key);

      if p <> nil then
        Current := p
      else
        Current := nil;
    end else
      Current := p;
  end else
    Current := nil;
end;

procedure THash<K, V>.SetMap(Key: K; const Value: V; NewItem: PItem; const wait : TSpinWait);
var
  p, pNew, pDisp, pPrior : PItem;
  iDepth, idx : Integer;
  bSuccess : boolean;
begin
  if NewItem = nil then
  begin
    New(pNew);
    pNew.Key := Key;
    pNew.Value := Value;
  end else
    pNew := NewItem;
  pNew.Next := nil;

  idx := GetHashIndex(Key);
  pPrior := nil;
  GetMapPointer(Key, idx, pPrior, p, iDepth);
  if (iDepth > 0) and (p = nil) then
  begin
    // Slot occupied but key not found
    pNew.Next := p;
    TInterlocked.CompareExchange(pPrior^.Next, pNew, p, bSuccess);
    if not bSuccess then
    begin
      wait.SpinCycle;
      SetMap(Key,Value, pNew, wait);
    end;
  end else if (iDepth > 0) and (p <> nil) then
  begin
    // Slot occupied but key found in linked list
    pDisp := p;
    pNew.Next := p^.Next;
    TInterlocked.CompareExchange(pPrior^.Next, pNew, p, bSuccess);
    if not bSuccess then
    begin
      wait.SpinCycle;
      SetMap(Key,Value, pNew, wait);
    end else
    begin
      Dispose(pDisp);
    end;
  end else if (iDepth = 0) and (p <> nil) then
  begin
    // Slot occupied byt key starts linked list
    pDisp := p;
    pNew.Next := p^.Next;
    TInterlocked.CompareExchange(FItems[idx], pNew, p, bSuccess);
    if not bSuccess then
    begin
      wait.SpinCycle;
      SetMap(Key,Value, pNew, wait);
    end else
    begin
      Dispose(pDisp);
    end;
  end else if (iDepth = 0) and (p = nil) then
  begin
    // Slot open, start linked list with key
    TInterlocked.CompareExchange(FItems[idx],pNew,p,bSuccess);
    if not bSuccess then
    begin
      wait.SpinCycle;
      SetMap(Key,Value, pNew, wait);
    end else
      if p <> nil then
        Dispose(p);
  end else
    raise Exception.Create('Invalid Hash State.');
end;

procedure THash<K, V>.SetMap(Key: K; const Value: V);
var
  sw : TSpinWait;
begin
  sw.Reset;
  SetMap(Key, Value, nil, sw);
end;

end.
