const COLORS = [
  'bg-violet-500', 'bg-blue-500', 'bg-emerald-500', 'bg-orange-500',
  'bg-pink-500', 'bg-teal-500', 'bg-amber-500', 'bg-red-500',
]

export default function Dashboard({ report }) {
  if (!report) return null

  const max = Math.max(...report.by_category.map((c) => c.total), 1)

  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
      <div className="bg-gradient-to-br from-violet-600 to-violet-800 rounded-2xl p-6 text-white">
        <p className="text-violet-200 text-sm font-medium mb-1">Total This Month</p>
        <p className="text-4xl font-bold">₹{report.total_spent.toLocaleString()}</p>
        <p className="text-violet-200 text-sm mt-2">{report.expense_count} transactions</p>
      </div>

      <div className="md:col-span-2 bg-white rounded-2xl p-6 shadow-sm">
        <p className="text-sm font-semibold text-slate-500 uppercase tracking-wide mb-4">Spending by Category</p>
        {report.by_category.length === 0 ? (
          <p className="text-slate-400 text-sm">No expenses yet this month.</p>
        ) : (
          <div className="space-y-3">
            {report.by_category.map((cat, i) => (
              <div key={cat.category}>
                <div className="flex justify-between text-sm mb-1">
                  <span className="font-medium text-slate-700">{cat.category}</span>
                  <span className="text-slate-500">₹{cat.total.toLocaleString()}</span>
                </div>
                <div className="h-2 bg-slate-100 rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full ${COLORS[i % COLORS.length]}`}
                    style={{ width: `${(cat.total / max) * 100}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
