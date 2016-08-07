
sanitize(x) = x
sanitize(ex::Expr) = sanitize(to_exh(ex))
sanitize(ex::LineNumberNode) = nothing
sanitize(ex::ExH{:return}) = ex.args[1]


function sanitize(ref::GlobalRef)
    # experimental: replace GlobalRef to function to actual function name
    return ref.name
end

function sanitize{H}(ex::ExH{H})
    sanitized_args = [sanitize(arg) for arg in ex.args]
    new_args = filter(arg -> arg != nothing, sanitized_args)
    return Expr(H, new_args...)
end



if VERSION < v"0.5.0-"

    # TODO: find out how to do it on Julia 0.5

    function funexpr(f::Function, types::Vector{DataType})
        fs = methods(f, types)
        length(fs) != 1 && error("Found $(length(fs)) methods for function $f " *
                                 "with types $types, expected exactly 1 method")
        fdef = fs[1].func.code
        flambda = Base.uncompressed_ast(fdef)
        fcode = flambda.args[3]
        fargs = flambda.args[1]
        return fargs, types, sanitize(fcode)
    end

end
