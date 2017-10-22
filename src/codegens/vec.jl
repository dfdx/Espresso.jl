
# type for generating vectorized code
struct VectorCodeGen
end


function generate_code(::VectorCodeGen, g::ExGraph, nd::ExNode)
    ex = to_expr(nd)
    return ex
end


function generate_code(::VectorCodeGen, g::ExGraph)
    ex = to_expr(g)
    return ex
end

