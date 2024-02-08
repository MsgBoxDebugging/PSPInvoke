class PSStruct{
    hidden $formatCharacters = @{
        [char]'x'=[byte];
        [char]'c'=[char];
        [char]'b'=[byte];
        [char]'B'=[byte]; 
        [char]'?'=[byte]; 
        [char]'h'=[int16];
        [char]'H'=[uint16];
        [char]'i'=[int32];
        [char]'I'=[uint32];
        [char]'l'=[int32];
        [char]'L'=[uint32];
        [char]'q'=[int64];
        [char]'Q'=[uint64];
        [char]'f'=[single];
        [char]'d'=[double];
        [char]'s'=[byte];
        [char]'S'=[byte];
        [char]'p'=[byte];
    }
    hidden $regex_Fmt = "^(<)?([0-9]*[xcbBhHiIlLqQfdsS])+"
    PSStruct(){}

    [object] calcSize([String] $layout, [bool] $returnMatches){
        $matches = [System.Text.RegularExpressions.Regex]::new($this.regex_Fmt).match($layout)
        if(-not $matches.Success -or $matches.Length -ne $layout.Length){Throw "Error PSStruct.calcSize(`"{0:s}`"): Invalid character '{1:c}'" -f $layout, $layout[$matches.Length]}

        $size = 0
        foreach($capture in $matches.Groups[2].Captures){
            $count = [int]$capture.value.Substring(0,$capture.value.Length-1);if($count -eq 0){$count++}
            $type = [Convert]::ChangeType(0,$this.formatCharacters[[char]$capture.value[-1]])
            $size += $count * [Runtime.InteropServices.Marshal]::SizeOf($type)
        }
        if($returnMatches) {return @($size,$matches)}
        else {return $size}
    }

    [object] calcSize([String] $layout){
        return $this.calcSize($layout,$false)
    }

    [byte[]] pack([String] $layout, [object[]] $elements){
        $matches = [System.Text.RegularExpressions.Regex]::new($this.regex_Fmt).match($layout)
        if(-not $matches.Success -or $matches.Length -ne $layout.Length){Throw "Error PSStruct.pack(`"{0:s}`"): Invalid character '{1:c}'" -f $layout, $layout[$matches.Length]}

        try {
            $elementIndex = 0
            $stream = [System.IO.MemoryStream]::new()
            foreach($capture in $matches.Groups[2].Captures){
                $count = [int]$capture.value.Substring(0,$capture.value.Length-1);if($count -eq 0){$count++}
                $type = $this.formatCharacters[[char]$capture.value[-1]]
                for($c = 0; $c -lt $count; $c++,$elementIndex++){
                    $typeInstance = [Convert]::ChangeType($elements[$elementIndex],$type)
                    $instanceSize = [Runtime.InteropServices.Marshal]::SizeOf($typeInstance)
                    $stream.write([System.BitConverter]::GetBytes($typeInstance),0,$instanceSize)
                }
            }
        }
        catch {Throw "Error PSStruct.pack(`"{0:s}`"): Insufficent arguments, expected {1:d} only recieved {2:d}" -f $layout, $matches.Groups[2].Captures.Count,$elements.Length}
        return ([byte[]]$stream.ToArray())
    }

    [Object] unpack([String] $layout, [object] $pointer, [uint64] $offset){
        $size, $matches = $this.calcSize($layout,$true)
        $bytes = $null
        if([uint64].IsInstanceOfType($pointer)){$pointer = [IntPtr]::new($pointer)}
        if([IntPtr].IsInstanceOfType($pointer)){$bytes = [byte[]]::new($size);[Runtime.InteropServices.Marshal]::Copy($pointer,$bytes,0,$size)}
        else{$bytes = $pointer}

        $unpackedValues = [System.Collections.ArrayList]::new()
        Add-Member -InputObject $unpackedValues -MemberType NoteProperty -Name StructSize -Value $size
        foreach($capture in $matches.Groups[2].Captures){
            $count = [int]$capture.value.Substring(0,$capture.value.Length-1);if($count -eq 0){$count++}
            $type = [char]$capture.value[-1]
            for($c = 0; $c -lt $count; $c++){
                $value = $null
                switch ($type) {
                    'x' {$offset+=1;break}
                    'c' {$value = [char]$bytes[$offset];$offset+=1;break}
                    'b' {$value = [byte]$bytes[$offset];$offset+=1;break}
                    'B' {$value = [byte]$bytes[$offset];$offset+=1;break}
                    '?' {$value = [bool]$bytes[$offset];$offset+=1;break}
                    'h' {$value = [BitConverter]::ToInt16($bytes, $offset);$offset+=2;break}
                    'H' {$value = [BitConverter]::ToUInt16($bytes, $offset);$offset+=2;break}
                    'i' {$value = [BitConverter]::ToInt32($bytes, $offset);$offset+=4;break}
                    'I' {$value = [BitConverter]::ToUInt32($bytes, $offset);$offset+=4;break}
                    'l' {$value = [BitConverter]::ToInt32($bytes, $offset);$offset+=4;break}
                    'L' {$value = [BitConverter]::ToUInt32($bytes, $offset);$offset+=4;break}
                    'q' {$value = [BitConverter]::ToInt64($bytes, $offset);$offset+=8;break}
                    'Q' {$value = [BitConverter]::ToUInt64($bytes, $offset);$offset+=8;break}
                    's' {$value = [Text.Encoding]::ASCII.GetString($bytes,$offset,$count);$offset+=$count;break}
                    'S' {$value = [Text.Encoding]::Unicode.GetString($bytes,$offset,$count);$offset+=$count;break}
                }
                if($value -ne $null){$null = $unpackedValues.add($value)}
                if($type -eq 's' -or $type -eq 'S'){break}
            }
        }
       
        return $unpackedValues
    }
}