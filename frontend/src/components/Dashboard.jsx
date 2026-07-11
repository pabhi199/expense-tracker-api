const COLORS = ['#7c3aed', '#2563eb', '#059669', '#d97706', '#db2777', '#0891b2', '#65a30d', '#dc2626']

export default function Dashboard({ report }) {
  if (!report) return null

  const max = Math.max(...report.by_category.map((c) => c.total), 1)
  const topCategory = report.by_category[0]

  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">

      {/* Total card */}
      <div className="relative overflow-hidden rounded-2xl p-6" style={{ background: 'linear-gradient(135deg, #7c3aed 0%, #a855f7 100%)' }}>
        <div className="absolute -top-6 -right-6 w-32 h-32 rounded-full opacity-20" style={{ background: 'white' }} />
        <div className="absolute -bottom-8 -left-4 w-24 h-24 rounded-full opacity-10" style={{ background: 'white' }} />
        <p className="text-sm font-medium text-purple-200 mb-1">Total Spent</p>
        <p className="text-4xl font-bold text-white mb-1">₹{report.total_spent.toLocaleString()}</p>
        <p className="text-sm text-purple-200">{report.by_category.length} categories used</p>
      </div>

      {/* Transaction count */}
      <div className="rounded-2xl p-6" style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}>
        <p className="text-sm font-medium mb-1" style={{ color: 'rgba(255,255,255,0.5)' }}>Transactions</p>
        <p className="text-4xl font-bold text-white mb-1">{report.expense_count}</p>
        <p className="text-sm" style={{ color: 'rgba(255,255,255,0.4)' }}>
          {report.expense_count > 0
            ? `Avg ₹${Math.round(report.total_spent / report.expense_count).toLocaleString()} each`
            : 'No expenses yet'}
        </p>
      </div>

      {/* Top category */}
      <div className="rounded-2xl p-6" style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}>
        <p className="text-sm font-medium mb-1" style={{ color: 'rgba(255,255,255,0.5)' }}>Top Category</p>
        {topCategory ? (
          <>
            <p className="text-2xl font-bold text-white mb-1">{topCategory.category}</p>
            <p className="text-sm" style={{ color: 'rgba(255,255,255,0.4)' }}>₹{topCategory.total.toLocaleString()} spent</p>
          </>
        ) : (
          <p className="text-2xl font-bold text-white">—</p>
        )}
      </div>

      {/* Category breakdown */}
      {report.by_category.length > 0 && (
        <div className="md:col-span-3 rounded-2xl p-6" style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}>
          <p className="text-sm font-semibold uppercase tracking-widest mb-5" style={{ color: 'rgba(255,255,255,0.4)' }}>Breakdown by Category</p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {report.by_category.map((cat, i) => (
              <div key={cat.category}>
                <div className="flex justify-between text-sm mb-2">
                  <div className="flex items-center gap-2">
                    <div className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: COLORS[i % COLORS.length] }} />
                    <span className="font-medium text-white">{cat.category}</span>
                  </div>
                  <div className="text-right">
                    <span className="font-semibold text-white">₹{cat.total.toLocaleString()}</span>
                    <span className="ml-2 text-xs" style={{ color: 'rgba(255,255,255,0.4)' }}>
                      {Math.round((cat.total / report.total_spent) * 100)}%
                    </span>
                  </div>
                </div>
                <div className="h-1.5 rounded-full overflow-hidden" style={{ background: 'rgba(255,255,255,0.08)' }}>
                  <div
                    className="h-full rounded-full transition-all duration-700"
                    style={{ width: `${(cat.total / max) * 100}%`, background: COLORS[i % COLORS.length] }}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
