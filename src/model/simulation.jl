#################### Model Simulation Methods ####################

function gradlogpdf(m::Model, block::Integer=0, transform::Bool=false;
           dtype::Symbol=:forward)
  x0 = unlist(m, block, transform)
  value = gradlogpdf!(m, x0, block, transform, dtype=dtype)
  relist!(m, x0, block, transform)
  value
end

function gradlogpdf{T<:Real}(m::Model, x::Vector{T}, block::Integer=0,
           transform::Bool=false; dtype::Symbol=:forward)
  x0 = unlist(m, block)
  value = gradlogpdf!(m, x, block, transform, dtype=dtype)
  relist!(m, x0, block)
  value
end

function gradlogpdf!{T<:Real}(m::Model, x::Vector{T}, block::Integer=0,
           transform::Bool=false; dtype::Symbol=:forward)
  f = x -> logpdf!(m, x, block, transform)
  gradient(f, x, dtype)
end

function logpdf(m::Model, block::Integer=0, transform::Bool=false)
  value = 0
  if block > 0
    sampler = m.samplers[block]
    params = sampler.params
    nkeys = [setdiff(params, sampler.targets), sampler.targets]
  else
    params = keys(m, :block)
    nkeys = m.dependents
  end
  for key in nkeys
    value += logpdf(m[key], transform && in(key, params))
    isfinite(value) || break
  end
  value
end

function logpdf{T<:Real}(m::Model, x::Vector{T}, block::Integer=0,
           transform::Bool=false)
  x0 = unlist(m, block)
  value = logpdf!(m, x, block, transform)
  relist!(m, x0, block)
  value
end

function logpdf!{T<:Real}(m::Model, x::Vector{T}, block::Integer=0,
           transform::Bool=false)
  value = 0
  if block > 0
    sampler = m.samplers[block]
    params = sampler.params
    targets = sampler.targets
  else
    params = keys(m, :block)
    targets = m.dependents
  end
  m[params] = relist(m, x, params, transform)
  for key in setdiff(params, targets)
    value += logpdf(m[key], transform)
    isfinite(value) || return value
  end
  for key in targets
    update!(m[key], m)
    value += logpdf(m[key], transform && in(key, params))
    isfinite(value) || return value
  end
  value
end

function relist{T<:Real}(m::Model, values::Vector{T}, block::Integer=0,
           transform::Bool=false)
  relist(m, values, keys(m, :block, block), transform)
end

function relist{T<:Real}(m::Model, values::Vector{T}, nkeys::Vector{Symbol},
           transform::Bool=false)
  x = (Symbol => Any)[]
  j = 0
  for key in nkeys
    node = m[key]
    n = node.nlink
    x[key] = invlink(node, values[j+(1:n)], transform)
    j += n
  end
  j == length(values) || throw(ErrorException("argument dimensions must match"))
  x
end

function relist!{T<:Real}(m::Model, values::Vector{T}, block::Integer=0,
           transform::Bool=false)
  nkeys = keys(m, :block, block)
  m[nkeys] = relist(m, values, nkeys, transform)
  update!(m, block)
end

function relist!{T<:Real}(m::Model, values::Vector{T}, nkeys::Vector{Symbol},
           transform::Bool=false)
  m[nkeys] = relist(m, values, nkeys, transform)
  update!(m)
end

function simulate!(m::Model, block::Integer=0)
  if block > 0
    blocks = block
  else
    m.iter += 1
    blocks = 1:length(m.samplers)
  end
  for b in blocks
    sampler = m.samplers[b]
    value = sampler.eval(m, b)
    if value != nothing
      m[sampler.params] = value
      update!(m, b)
    end
  end
  m
end

function unlist(m::Model, block::Integer=0, transform::Bool=false)
  unlist(m, keys(m, :block, block), transform)
end

function unlist(m::Model, monitoronly::Bool)
  values = VariateType[]
  for key in keys(m, :dependent)
    node = m[key]
    lvalue = [link(node, node.value, false)]
    v = monitoronly ? lvalue[node.monitor] : vec(lvalue)
    append!(values, v)
  end
  values
end

function unlist(m::Model, nkeys::Vector{Symbol}, transform::Bool=false)
  N = Integer[m[key].nlink for key in nkeys]
  values = Array(VariateType, sum(N))
  i = 0
  for k in 1:length(nkeys)
    node = m[nkeys[k]]
    n = N[k]
    values[i+(1:n)] = link(node, node.value, transform)
    i += n
  end
  values
end

function update!(m::Model, block::Integer=0)
  nkeys = block > 0 ? m.samplers[block].targets : m.dependents
  for key in nkeys
    update!(m[key], m)
  end
  m
end
