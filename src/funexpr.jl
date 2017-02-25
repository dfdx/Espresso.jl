
# funexpr.jl - extract arguments and (sanitized) expression of a function body.
#
# Here sanitization means removing things like LineNumberNode and replacing
# hard-to-consume nodes (e.g. `GloabalRef` and `return`) with their simple
# counterparts (e.g. expression with `.` and variable node).

sanitize(x) = x
sanitize(ex::Expr) = sanitize(to_exh(ex))
sanitize(ex::LineNumberNode) = nothing
sanitize(ex::ExH{:line}) = nothing
sanitize(ex::ExH{:return}) = ex.args[1]

function sanitize(ex::ExH{:block})
    sanitized_args = [sanitize(arg) for arg in ex.args]
    new_args = filter(arg -> arg != nothing, sanitized_args)
    return length(new_args) == 1 ? new_args[1] : Expr(ex.head, new_args...)
end

function sanitize{H}(ex::ExH{H})
    sanitized_args = [sanitize(arg) for arg in ex.args]
    new_args = filter(arg -> arg != nothing, sanitized_args)
    return Expr(H, new_args...)
end

function sanitize(ref::GlobalRef)
    # mod = Main # module doesn't actually matter since GlobalRef contains it anyway
    # return canonical(mod, ref)
    return Expr(:., ref.mod, QuoteNode(ref.name))
end


if VERSION < v"0.5.0-"

    """Extract arguments and (sanitized) expression of a function body"""
    function funexpr{N}(f::Function, types::NTuple{N,DataType})
        fs = methods(f, types)
        length(fs) != 1 && error("Found $(length(fs)) methods for function $f " *
                                 "with types $types, expected exactly 1 method")
        fdef = fs[1].func.code
        flambda = Base.uncompressed_ast(fdef)
        fcode = flambda.args[3]
        fargs = flambda.args[1]
        return fargs, sanitize(fcode)
    end

elseif VERSION < v"0.6.0-"

    function replace_slots(ex::Expr, slotnames::Vector)
        new_args = Array(Any, length(ex.args))
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

    """Extract arguments and (sanitized) expression of a function body"""
    function funexpr{N}(f::Function, types::NTuple{N,DataType})
        ms = methods(f, types).ms
        length(ms) != 1 && error("Found $(length(ms)) methods for function $f " *
                                 "with types $types, expected exactly 1 method")
        lambda = ms[1].lambda_template
        slot_ex_arr = Base.uncompressed_ast(lambda)
        slot_ex = sanitize(Expr(:block, slot_ex_arr...))
        slotnames = lambda.slotnames
        ex = replace_slots(slot_ex, slotnames)
        # 1st arg is a function name, next `lambda.nargs-1` are actual arg names
        args = map(Symbol, slotnames[2:lambda.nargs])
        return args, sanitize(ex)
    end

else

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
        return [isa(arg,  Symbol) ? arg : arg.args[1] for arg in sig.args[2:end]]
    end


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


    function funexpr{N}(f::Function, types::NTuple{N,DataType})
        method = Sugar.get_method(f, types)
        file = string(method.file)
        linestart = method.line
        try
            code, _ = Sugar.get_source_at(file, linestart)
            return arg_names(code.args[1]), sanitize(code.args[2])
        catch err
            if isa(err, LoadError)
                code = code_lowered(f, types)[1]
                return to_expr(code)
            else
                rethrow(err)
            end
        end
    end

end
