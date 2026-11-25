-- Recipe catalog. The catalog contains authoritative exported recipe data,
-- never inferred fluid ratios. Missing/ambiguous matches fail closed.
local M={}
local function id(v) return type(v)=="string" and v:match("^[%w_.-]+:[%w_./-]+$")~=nil end
local function list(v) return type(v)=="table" and #v>0 end
local function validAmount(n) return type(n)=="number" and n%1==0 and n>0 and n<=1000000 end
function M.validate(doc)
  assert(type(doc)=="table" and doc.schema==1 and type(doc.filling)=="table","Invalid recipe catalog schema")
  local seen={}
  for _,r in ipairs(doc.filling) do
    assert(id(r.id) and not seen[r.id],"Invalid or duplicate recipe ID")
    seen[r.id]=true
    assert(list(r.items) and list(r.fluids) and validAmount(r.amount),"Invalid filling recipe: "..r.id)
    for _,v in ipairs(r.items) do assert(id(v),"Invalid item ID") end
    for _,v in ipairs(r.fluids) do assert(id(v),"Invalid fluid ID") end
  end
  assert(#doc.filling>0,"Empty filling catalog")
  return doc
end
local function has(a,v) for _,x in ipairs(a) do if x==v then return true end end return false end
function M.new(doc)
  local self={doc=doc}
  function self.replace(value) self.doc=M.validate(value) end
  function self.lookup(item,fluid)
    if not self.doc then return nil,"RECIPE CATALOG MISSING" end
    local amount,recipe
    for _,r in ipairs(self.doc.filling) do
      if has(r.items,item.name) and has(r.fluids,fluid) then
        if r.nbtSensitive then return nil,"RECIPE COMPONENT MATCH REQUIRED" end
        if amount and amount~=r.amount then return nil,"AMBIGUOUS FILLING RECIPE" end
        amount=r.amount; recipe=r.id
      end
    end
    if not amount then return nil,"FILLING RECIPE NOT FOUND" end
    return amount,nil,recipe
  end
  return self
end
return M
