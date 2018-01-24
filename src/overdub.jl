
## homegrown alternative to Cassette.jl, solely experimental/educational


@generated function overdub(f, args...)
    code = lookup_method_body(Tuple{f, args...})
    println("calling function $f")
    return :(f(args...))
end



bar(y) = x + 1

foo(x) = 2 * bar(x)



function lookup_method(fn, types)
    Base._methods_by_ftype(Tuple{typeof(fn), types...}, -1, typemax(UInt))[0]    
end
