
## homegrown alternative to Cassette.jl, solely experimental/educational


struct Overdub{F,w}
    world::Val{w}
    func::F
    args::Any    
end

Overdub(func, args...) = Overdub(Val(get_world_age()), func, args)


get_world_age() = ccall(:jl_get_tls_world_age, UInt, ())


function lookup_method(S, world)
    _methods = Base._methods_by_ftype(S, -1, world)
    length(_methods) == 1 || return nothing
    type_signature, raw_static_params, method = first(_methods)
    method_instance = Core.Compiler.code_for_method(method, type_signature,
                                                    raw_static_params, world, false)
    method_signature = method.sig
    static_params = Any[raw_static_params...]
    code_info = Core.Compiler.retrieve_code_info(method_instance)
    isa(code_info, CodeInfo) || return nothing
    code_info = Core.Compiler.copy_code_info(code_info)
    return code_info
end


function overdub_calls!(code::CodeInfo, w)
    for i=1:length(code.code)
        if isa(code.code[i], Expr)
            code.code[i] = rewrite_all(code.code[i], [:(_f(_args...)) =>
                                                      :(Overdub(Val($w), _f, _args...)(_args...))])
        end
    end
    return code
end

overdub_calls!(::Nothing) = nothing


@generated function (f::Overdub{F,world})(args...) where {F,world}
    signature = Tuple{F,args...}
    code_info = lookup_method(signature, world)
    println("calling $F, original code is: $code_info")
    if isa(code_info, CodeInfo)
        new_code_info = overdub_calls!(code_info, world)
    else
        println("args are: $args")
        new_code_info = :(f.func(args...))
        # new_code_info = nothing
    end
    println("calling $F, code after transformation: $new_code_info")
    return new_code_info
end



## for tests

bar(y::Int) = (println("runtime"); y + 1)

foo(x::Int) = 2 * bar(x)


function _main()
    Overdub(foo)(11)
end
