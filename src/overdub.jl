
## homegrown alternative to Cassette.jl, solely experimental/educational

import Cassette: lookup_method_body
# import Espresso: rewrite_all


function overdub_calls!(code::CodeInfo, w::Val{W}) where W
    for i=1:length(code.code)
        code.code[i] = rewrite_all(code.code[i], [:(_f(_args...)) => :(overdub($w, _f, _args...))])
    end    
end


@generated function overdub(w::Val{W}, f, args...) where W
    code = lookup_method_body(Tuple{f, args...})
    println(code)
    println("calling function $f")
    overdub_calls!(code, w)
    # return :(f(args...))
    return :(f(args...))
end



bar(y) = y + 1

foo(x) = 2 * bar(x)






# function lookup_method(fn, types)
#     Base._methods_by_ftype(Tuple{typeof(fn), types...}, -1, typemax(UInt))[0]    
# end
