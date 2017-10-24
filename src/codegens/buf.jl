
struct BufCodeGen
    eltyp::Type
end

BufCodeGen() = BufCodeGen(Float64)


function buffer_expr(var, eltyp, buffer_var, sz)
    if isempty(sz)
        return :($var = $eltyp(0.0))
    else
        return :($var = @get_or_create($buffer_var, $(Expr(:quote, var)),
                                        Array(zeros($eltyp, $sz))))
    end
end


function generate_code(codegen::BufCodeGen, g::ExGraph, nd::ExNode)
    # nd = cast_const_type(nd, codegen.eltyp)
    ex = to_buffered(g, nd)
    return ex
end


function generate_code(codegen::BufCodeGen, g::ExGraph)
    g = eliminate_common(g)
    # g = cast_const_type(g, codegen.eltyp)
    ex = to_buffered(g)
    init_exs = [buffer_expr(var, codegen.eltyp, :mem, sz) for (var, sz) in g.ctx[:rsizes]
                if haskey(g, var) && getcategory(g[var]) != :input]
    res = Expr(:block, init_exs..., ex.args...)
    return res
end


eval_codegen(codegen::BufCodeGen) = VectorCodeGen(codegen.eltyp)
