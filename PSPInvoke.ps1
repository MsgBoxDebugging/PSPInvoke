class PSPInvoke{
    hidden [Hashtable] $importTable
    hidden [MulticastDelegate] $CreateDelegate = $NULL
    hidden [Reflection.MethodInfo] $CreateFunction = $NULL
    hidden [Reflection.MethodInfo] $LoadLibraryInternal = $NULL
    hidden [Reflection.MethodInfo] $GetProcAddressInternal = $NULL

    PSPInvoke(){
        $this.importTable = @{}
        $loaded = [AppDomain]::CurrentDomain.GetAssemblies()
        $system_core = $loaded | WHERE {$_.getname().name -eq "System.Core"}
        $mscorlib = $loaded | WHERE {$_.getname().name -eq "mscorlib"}
        $system = $loaded | WHERE {$_.getna).name -eq "System"}
        $methodHandle = ($system_core.DefinedTypes | WHERE name -eq DelegateHelpers).DeclaredMethods | WHERE name -eq MakeNewCustomDelegate | SELECT -first 1
        
        $this.CreateDelegate = [Delegate]::CreateDelegate([func[[Type[]],Type]],$methodHandle)
        $this.CreateFunction = ($mscorlib.DefinedTypes | WHERE name -eq Marshal).DeclaredMethods | WHERE name -eq GetDelegateForFunctionPointer | SELECT -first 1 
        $this.LoadLibraryInternal = ($system.DefinedTypes | WHERE name -eq SafeNativeMethods | SELECT -first 1).DeclaredMethods | WHERE name -eq LoadLibrary
        $this.GetProcAddressInternal = ($system.DefinedTypes | WHERE name -eq UnsafeNativeMethods | SELECT -first 1).DeclaredMethods | WHERE name -eq GetProcAddress | SELECT -first 1
        if(-not ($this.CreateFunction -and $this.CreateDelegate -and $this.LoadLibraryInternal -and $this.GetProcAddressInternal)){Throw ("Error PSPInvoke.init(): Could not find required functions.")}
    }

    [Void] import([String] $module, [String]$functions){
        $Module = $module.ToUpper()
        $HModule = $this.LoadLibraryInternal.invoke(0,$module)
        if($HModule -eq 0 ){Throw ("Error PSPInvoke.import(): could not load {0:s}." -f ($module))}

        foreach($function in $functions.split(',').trim()){
            if($function -in $this.importTable.Keys){Continue}
            $farproc = $this.GetProcAddressInternal.Invoke(0,@(($HModule,$function)))
            if($farproc -eq 0){Throw ("Error PSPInvoke.import(): could not import {0:s}!{1:s}." -f ($module,$function))}
            $this.generateRuntimeFunctionPointer($function, $farproc)
        }
        return
    }
 
    hidden [Object] generateRuntimeMethod([String] $function, [Array]$arguments){
        $types = [type[]]::new($arguments.Length+1);for($i = 0;$i -lt $arguments.Length;$i++){$types[$i] = $arguments[$i].gettype()};$types[-1] = [uint64];  
        $this.importTable[$function] = $this.CreateFunction.Invoke(0,($this.importTable[$function],$this.CreateDelegate.Invoke($types)))
        $builder = [Text.StringBuilder]::new()
        $builder.Append("`$this | Add-Member -MemberType ScriptMethod -Name $function -Value {`$this.importTable['$function'].invoke(");
        for($i = 0;$i -lt $arguments.Length;$i++){$builder.Append("`$args[$i],")};$builder[-1] = ')';$builder.append('}');
        $this.PSObject.Properties.Remove($function)
        iex $builder.ToString()
        return (icm $this.PSObject.Members[$function].Script -ArgumentList $arguments)
    }

    [Void] generateRuntimeFunctionPointer([String] $name, [IntPtr] $farproc){
        if($farproc -eq 0){Throw ("Error PSPInvoke.generateRuntimeFunctionPointer(): pointer is null.")}
        $this.importTable.add($name, $farproc)
        iex "`$this | Add-Member -MemberType ScriptMethod -Name $name -Value {`$this.generateRuntimeMethod(`"$name`",[Array]`$args)}"
        return
    }
}