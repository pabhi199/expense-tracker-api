const CATEGORY_COLORS = [
  'bg-violet-100 text-violet-700',
  'bg-blue-100 text-blue-700',
  'bg-emerald-100 text-emerald-700',
  'bg-orange-100 text-orange-700',
  'bg-pink-100 text-pink-700',
  'bg-teal-100 text-teal-700',
  'bg-amber-100 text-amber-700',
  'bg-red-100 text-red-700',
]

function categoryColor(name) {
  let hash = 0
  for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash)
  return CATEGORY_COLORS[Math.abs(hash) % CATEGORY_COLORS.length]
}

export default function ExpenseList({ expenses, onEdit, onDelete }) {
  if (expenses.length === 0) {
    return (
      <div className="bg-white rounded-2xl shadow-sm p-12 text-center">
        <p className="text-5xl mb-3">💸</p>
        <p className="text-slate-500">No expenses yet. Add your first one!</p>
      </div>
    )
  }

  const grouped = expenses.reduce((acc, exp) => {
    const key = exp.category.name
    if (!acc[key]) acc[key] = []
    acc[key].push(exp)
    return acc
  }, {})

  return (
    <div className="space-y-4">
      {Object.entries(grouped).map(([category, items]) => {
        const total = items.reduce((s, e) => s + e.amount, 0)
        return (
          <div key={category} className="bg-white rounded-2xl shadow-sm overflow-hidden">
            <div className="flex items-center justify-between px-5 py-3 bg-slate-50 border-b border-slate-100">
              <span className={`text-xs font-semibold px-2.5 py-1 rounded-full ${categoryColor(category)}`}>
                {category}
              </span>
              <span className="text-sm font-semibold text-slate-700">₹{total.toLocaleString()}</span>
            </div>
            <div className="divide-y divide-slate-50">
              {items.map((exp) => (
                <div key={exp.id} className="flex items-center px-5 py-3 hover:bg-slate-50 group">
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-slate-800 truncate">{exp.title}</p>
                    {exp.notes && (
                      <p className="text-xs text-slate-400 truncate">{exp.notes}</p>
                    )}
                  </div>
                  <div className="text-right ml-4">
                    <p className="text-sm font-semibold text-slate-800">₹{exp.amount.toLocaleString()}</p>
                    <p className="text-xs text-slate-400">{exp.spent_on}</p>
                  </div>
                  <div className="ml-3 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    <button
                      onClick={() => onEdit(exp)}
                      className="p-1.5 rounded-lg text-slate-400 hover:text-violet-600 hover:bg-violet-50"
                      title="Edit"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                      </svg>
                    </button>
                    <button
                      onClick={() => onDelete(exp)}
                      className="p-1.5 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50"
                      title="Delete"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                      </svg>
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )
      })}
    </div>
  )
}
