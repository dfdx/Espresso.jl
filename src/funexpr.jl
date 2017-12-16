
# funexpr.jl - extract arguments and (sanitized) expression of a function body.
#
# Here sanitization means removing things like LineNumberNode and replacing
# hard-to-consume nodes (e.g. `GloabalRef` and `return`) with their simple
# counterparts (e.g. expression with `.` and variable node).

sanitize(x) = x
sanitize(ex::Expr) = sanitize(ExH(ex))
sanitize(ex::LineNumberNode) = nothing
sanitize(m::Module) = Symbol(string(m))
sanitize(ex::ExH{:line}) = nothing
sanitize(ex::ExH{:return}) = sanitize(ex.args[1])

function sanitize(ex::ExH{:block})
    sanitized_args = [sanitize(arg) for arg in ex.args]
    new_args = filter(arg -> arg != nothing, sanitized_args)
    return length(new_args) == 1 ? new_args[1] : Expr(ex.head, new_args...)
end


function sanitize(ex::ExH{:quote})
    return length(ex.args) == 1 ? QuoteNode(ex.args[1]) : ex
end


function sanitize(ex::ExH{H}) where H
    sanitized_args = [sanitize(arg) for arg in ex.args]
    new_args = filter(arg -> arg != nothing, sanitized_args)
    return Expr(H, new_args...)
end


function sanitize(ref::GlobalRef)
    return Expr(:., Symbol(string(ref.mod)), QuoteNode(ref.name))
end


## recover lowered

const RECOVER_LOWERED_RULES = [
    :(Base.broadcast(_f, _xs...)) => :(_f.(_xs...)),
    :(Base.broadcast(_m._f, _xs...)) => :(_m._f.(_xs...)),
    :(Base.literal_pow(Main.:^, _x, _v)) => :(_x ^ _v),
    :(Core.apply_type(Base.Val, _x)) => :_x,
]

"""
Try to recover an expression from a lowered form. Example:

    ex = (Main.sum)((Base.literal_pow)(Main.^, (Base.broadcast)(Main.-, (Main.predict)(W, b, x), y), (Core.apply_type)(Base.Val, 2)))
"""
recover_lowered(x) = x
recover_lowered(ex::Expr) = recover_lowered(ExH(ex))


function recover_lowered(ex::ExH{:block})
    recovered_args = [recover_lowered(arg) for arg in ex.args]
    new_args = filter(arg -> arg != nothing, recovered_args)
    return length(new_args) == 1 ? new_args[1] : Expr(ex.head, new_args...)
end


function recover_lowered(ex::ExH{:call})
    # recover arguments
    recovered_args = [recover_lowered(arg) for arg in ex.args[2:end]]
    new_args = filter(arg -> arg != nothing, recovered_args)
    ex = Expr(:call, ex.args[1], new_args...)
    # check patterns
    for (pat, rpat) in RECOVER_LOWERED_RULES
        rex = tryrewrite(ex, pat, rpat)
        if !isnull(rex)
            ex = get(rex)
            break
        end
    end
    ex = canonical_calls(@__MODULE__, ex) |> subs_bcast_with_dot
    return ex
end


function recover_lowered(ex::ExH{H}) where H
    recovered_args = [recover_lowered(arg) for arg in ex.args]
    new_args = filter(arg -> arg != nothing, recovered_args)
    return Expr(H, new_args...)
end



## funexpr


function replace_slots(ex::Expr, slotnames::Vector)
    new_args = Array{Any}(length(ex.args))
    for (i, arg) in enumerate(ex.args)
        if isa(arg, Slot)
            new_args[i] = slotnames[arg.id]
        elseif isa(arg, Expr)
            new_args[i] = replace_slots(arg, slotnames)
        else
            new_args[i] = arg
        end
    end
    new_ex = Expr(ex.head, new_args...)
    return new_ex
end


function arg_names(sig::Expr)
    # note: ignoring type parameters, may not always be the right thing
    while sig.head == :where
        sig = sig.args[1]
    end
    return [isa(arg, Symbol) ? arg : arg.args[1] for arg in sig.args[2:end]]    
end


# there's already func_name in utils.jl
# funname(f::Function) = (methods(f) |> first).name



function to_expr(src::CodeInfo)
    if isa(src.code, Array{Any,1})
        slotnames = [Symbol(name) for name in Base.sourceinfo_slotnames(src)]
        body = Expr(:body, src.code...)
        result = replace_slots(body, slotnames)
        return result
    else
        error("Can't convert CodeInfo to expression: CodeInfo is compressed: $src")
    end
end


function funexpr(f::Function, types::NTuple{N,DataType}) where N
    method = Sugar.get_method(f, types)
    file = string(method.file)
    linestart = method.line
    try
        code, _ = Sugar.get_source_at(file, linestart)
        return arg_names(code.args[1]), sanitize(code.args[2])
    catch err
        if isa(err, LoadError)
            code = code_lowered(f, types)[1]
            args = convert(Vector{Symbol}, code.slotnames[2:end])
            ex = to_expr(code) |> sanitize |> recover_lowered
            return args, ex
        else
            rethrow(err)
        end
    end
end

func_expr = funexpr
