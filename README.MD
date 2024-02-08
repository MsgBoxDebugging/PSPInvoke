# MsgBoxDebugging Presents PSPInvoke && PSStruct


## What do they do?
**PSPInvoke**: An easy platform invoke solution written in Powershell, it allows you to easily import and call unmanaged functions and at runtime.</br>
**PSStruct** : An easy?(I dont know about this one yet) struct solution written in Powershell, basically Python.Struct.

## Why?
I am working on a debugger and wanted a way for the user to easily script object/memory manipulation. I feel that doing it the safe way in .NET can be too much work sometimes. 

At its current state, I think these could be useful for others to use as a quick and easy way to mock up code and do reverse-engineering/malware analysis things.


## Future Plans?
 I want to make this generally a little safer to use, I have crashed numerous Powershell instances by calling functions incorrectly while mocking up some code. I think my next step is going to be finding a way to add an exception handler to the thread before the delegate is called to catch any process crashing errors. I also want to make some changes to PSStruct, I hastily threw it together to do what I needed. I think I am going to rewrite it to use with .NET structures and marshalling.
</br>

## Demo
 In the demo folder I have a pure Powershell implementation of a PE loader. It is currently configured to load Powershell into Powershell.
 What is a PE Loader? Are you lost, how did you end up here? Go visit 
 [IRED.TEAM](https://www.ired.team/offensive-security/code-injection-process-injection/reflective-dll-injection). Thanks for the boilerplate code [mantvydasb](https://github.com/mantvydasb/RedTeaming-Tactics-and-Techniques/commits?author=mantvydasb).

</br>

## How to use PS PInvoke 

#### Functions 
| Syntax      | Description |
| ----------- | ----------- |
| **Void Import([string] ModuleName, [string] FunctionName)**                               | Imports **FunctionName(s)** from **ModuleName**. 
| **Void GenerateRuntimeFunctionPointer([string] FunctionName, [IntPtr] FunctionAddress)**  | Using **FunctionAddress** imports **FunctionName**


#### To import an exported function from a module just call the import function.
```Powershell
Import-Module PSPInvoke.ps1
$API = [PSPInvoke]::new()  
$API.import("USER32", "MessageBoxA")  
$API.MessageBoxA(0,"Wow, that was easy!","MessageBoxA",0)  
```


#### To import a function that you have an address for, but no module just call generateRuntimeFunctionPointer

```Powershell
Import-Module PSPInvoke.ps1
$API = [PSPInvoke]::new()
$API.import("KERNEL32", "GetProcAddress")
$HMOD = ((gps -Id $PID).Modules | WHERE ModuleName -eq user32.dll).BaseAddress
$FARPROC = $API.GetProcAddress($HMOD,"MessageBoxA")
$API.generateRuntimeFunctionPointer("MessageBoxA", $FARPROC)
$Caption = "MessageBoxA"
$Text = "Wow, that was easy!"
$API.MessageBoxA(0,$Text,$Caption,0)
```


Now a few of you may have some questions so here are a few I think would be asked?

- How do you know how to marshal the data you are passing to these functions?
  - I **don't** know. I create a delegate that takes arguments based of the number and type used the **FIRST** time the function is invoked. If you mess up and forget to cast your types correctly best case scenario the function you called fails, worst case Powershell explodes and .NET sends a bunch of text to your console.

- Up there^ you used MessageBoxA and passed it $Caption, a powershell variable how?
  - Glad you noticed, you see the delegate that is created is specifally for Interop between managed and unmanaged code. CLR Knows that  you cannot passed unmanaged code a managed object, so under the hood in the MSIL it passes a reference to the string's buffer in memory. Do not take this for granted, this will not work for every type and will almost certainly not work for you own types, unless you defined it with structlayout.

- What types can I pass to managed code safely
  - You can pass [Blittable types](https://learn.microsoft.com/en-us/dotnet/framework/interop/blittable-and-non-blittable-types)(essentially primitives like byte, char, int, and their array variations)

- What about structs?
  - You can use my struct module, it is a knock-off python.struct.
  - OR you can Create blittable type array ie. [byte[]], write your data to it, pin it in memory with ```System.Runtime.InteropServices.GCHandle Alloc(System.Object value, System.Runtime.InteropServices.GCHandleType)```, grab the memory address from GCHandle object with AddrOfPinnedObject(), pass that to unmanaged code, do what you want with it, free it(or don't you are already doing this so you probably dont care that much).

- WideStrings/WCHAR?
  - Create a string using [System.Text.Encoding]::Unicode.GetString, and pass that.

</br>

## How to use PS STRUCT
A rough struct implementation that allows you to manipulate C-Style structs.

#### Functions 
| Syntax      | Description |
| ----------- | ----------- |
|**[uint32] calcSize([string] Layout)** | Calculates the size of **Layout**
|**[byte[]] pack([string] Layout, [object[]] Values)** | Packs **Values** into the format specified by **Layout**
|**[Object[]] unpack([string] Layout, [Object] Buffer, [object[]] Values)** | Unpacks **Values** from **Buffer** into the format specified by **Layout**.

```Powershell
Layout Characters
'x'=[byte]; # Padding
'c'=[char];
'b'=[byte];
'B'=[byte]; 
'?'=[byte]; 
'h'=[int16];
'H'=[uint16];
'i'=[int32];
'I'=[uint32];
'l'=[int32];
'L'=[uint32];
'q'=[int64];
'Q'=[uint64];
'f'=[single];
'd'=[double];
's'=[byte];
'S'=[byte];
'p'=[byte];
```

Calculates the size of a the layout "IHIL"

```Powershell
Import-Module PSStruct.ps1
$STRUCT = [PSStruct]::new()
$size = $STRUCT.calcSize('IHIL');
```

Packs 2 unsigned shorts and 4 Longs into a buffer

```Powershell
Import-Module PSStruct.ps1
$STRUCT = [PSStruct]::new()
$buffer = $STRUCT.pack('2H4l',@(1,2,3,4,5,6));
$bufferSize = $buffer.StructSize
```

Unpacks 2 unsigned shorts and 4 Longs into a buffer.

```Powershell
Import-Module PSStruct.ps1
$STRUCT = [PSStruct]::new()
$packed = [byte[]](1,0,2,0,3,0,0,0,4,0,0,0,5,0,0,0,6,0,0,0)
$values = $STRUCT.unpack('2H4l',$data,0);
```

Questions
  - Big Endian?
    - nope, not now
  - Unpack memory at pointer?
    - PSSTRUCT.Unpack will take a pointer or a byte array.

