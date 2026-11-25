// ProcessorOS recipe export for Minecraft 1.21.1 / Create 6 / KubeJS.
// Install in kubejs/server_scripts and reload. Exports resolved recipe IDs
// and concrete ingredient alternatives; never changes any recipe.
const PSORegistries = Java.loadClass('net.minecraft.core.registries.BuiltInRegistries')
ServerEvents.afterRecipes(event => {
  const rows = []
  const errors = []
  event.forEachRecipe({type: 'create:filling'}, holder => {
    const id = String(holder.getOrCreateId())
    try {
      const recipe = holder.value()
      const ingredients = recipe.getIngredients()
      const fluids = recipe.getFluidIngredients()
      if (ingredients.size() !== 1 || fluids.size() !== 1) throw new Error('Unsupported ingredient count')
      const ing = ingredients.get(0)
      const fluid = fluids.get(0)
      const items = Array.from(ing.getItems()).map(s => String(PSORegistries.ITEM.getKey(s.getItem())))
      const stacks = Array.from(fluid.getFluids())
      const names = stacks.map(s => String(PSORegistries.FLUID.getKey(s.getFluid())))
      const amount = Number(fluid.amount())
      if (!items.length || !names.length || !(amount > 0)) throw new Error('Empty ingredient')
      // Conservative: custom item ingredient predicates or component constraints
      // require a stronger matcher than a registry ID.
      const sensitive = !ing.isSimple()
      rows.push({id:id,items:[...new Set(items)],fluids:[...new Set(names)],amount:amount,nbtSensitive:sensitive})
    } catch (err) { errors.push(id + ': ' + err) }
  })
  JsonIO.write('kubejs/processoros-recipes.json', {schema:1, filling:rows, errors:errors})
  console.info('ProcessorOS: exported ' + rows.length + ' filling recipes; skipped ' + errors.length)
})
