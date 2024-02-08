# Loads a PE file using the PSPInvoke PSStruct
# This demo reads in powershell of the disk and loads it into memory. 

Import-Module ..\PSPInvoke.ps1
Import-Module ..\PSStruct.ps1
$API = [PSPInvoke]::new()
$STRUCT = [PSStruct]::new()

$API.import("Kernel32","VirtualAlloc,LoadLibraryA,GetProcAddress,CreateThread")
$API.import('msvcrt','malloc,memset,memcpy,free')

$modulePath = (where.exe powershell)
$moduleBytes = [IO.File]::ReadAllBytes($modulePath)
$modulePtr = [Runtime.InteropServices.GCHandle]::Alloc($moduleBytes,3).AddrOfPinnedObject()

$offset = 0
$dosHeaders = $STRUCT.unpack('31H',$moduleBytes,0); 
$offset += $dosHeaders[-1]
$ntHeaders  = $STRUCT.unpack('L',$moduleBytes,$offset); 
$offset += $ntHeaders.StructSize
$fileHeader = $STRUCT.unpack('HHLLLHH',$moduleBytes,$offset); 
$offset +=  $fileHeader.StructSize
$optionalHeader = $STRUCT.unpack('H2B5L1Q2L6H4L2H4Q2HHxx',$moduleBytes,$offset); 
$offset += $optionalHeader.StructSize
$dataDirectory = $STRUCT.unpack(('{0:d}Q' -f $optionalHeader[-1]),$moduleBytes,$offset);
$offset += $dataDirectory.StructSize

$imageBase = [uint64]$API.VirtualAlloc([uint64]$optionalHeader[8],[int64]$optionalHeader[18],0x3000,64)
$imageDelta = [uint64]$imageBase - [uint64]$optionalHeader[8]
$null = $API.memcpy($imageBase,$modulePtr,$optionalHeader[19])
for($i=0;$i -lt $fileHeader[1];$i++){
    $section = $STRUCT.unpack('8s6L2HL',$moduleBytes,$offset); 
    $offset += $section.StructSize
    $null = $API.memcpy(($imageBase + $section[2]),($modulePtr.ToInt64() + $section[4]),$section[3])
}

$relocationDirectory = $dataDirectory[5]
$relocationTable = (($relocationDirectory -shl 32) -shr 32) + $imageBase
$relocationSize  = ($relocationDirectory -shr 32)
$relocationOffset = 0
while($relocationOffset -lt $relocationSize){ 
    $block = $STRUCT.unpack('LL',$relocationTable, 0); 
    $relocationOffset += 4  
    $relocationsCount = ($block[1] - 8) / 2;

    for($i = 0;$i -lt $relocationsCount; $i++){
        $entry = $STRUCT.unpack('H',($relocationTable+$relocationOffset), 0); 
        $relocationOffset += $STRUCT.calcSize('H')
        $entry_offset = ($entry[0] -band 0xfff)
        $entry_type = (($entry[0] -shr 12) -band 0xf)
        if($entry_type -eq 0){continue}

        $relocationRVA = $block[0] + $entry_offset
        $relocationValue = $STRUCT.unpack('Q',($imageBase+$relocationRVA),0)
        $relocationValue += $imageDelta
        [Runtime.InteropServices.Marshal]::WriteInt64([intptr]::new($imageBase+$relocationRVA),$relocationValue[0])
    }
}

$importDirectory = (($dataDirectory[1] -shl 32) -shr 32)
$importDescriptorCount = 0
while($true){
    $importDescriptorAddress = ($imageBase + $importDirectory + $importDescriptorCount)
    $importDescriptor = $STRUCT.unpack('LLLLL',$importDescriptorAddress,0)
    if($importDescriptor[-2] -eq 0){break}

    $hmodule = $API.LoadLibraryA(($imageBase + $importDescriptor[-2]))

    if($hmodule){
        $thunkCount = 0
        while($True){
            $thunkPointer = [intptr]::new($imageBase + $importDescriptor[-1] + $thunkCount)
            $thunk = [Runtime.InteropServices.Marshal]::ReadInt64($thunkPointer)
            if($thunk -eq 0){break}

            if($thunk[0] -band 0x8000000000000000){$lookup = $thunk[0] -band 0xFFFF}
            else{$lookup = $imageBase + $thunk[0] + 2}
            
            $farproc = $API.GetProcAddress($hmodule,$lookup)
            [Runtime.InteropServices.Marshal]::WriteInt64($thunkPointer,$farproc)
            $thunkCount += 8
        }
    }
    $importDescriptorCount += $STRUCT.calcSize('LLLLL')
}

$entrypoint = $imageBase + $optionalHeader[6]
$null = $API.CreateThread([uint64]0,[uint64]0,$entrypoint,[uint64]0,0,0)
