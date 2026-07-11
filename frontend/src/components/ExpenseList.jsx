const PALETTE = [
  { bg: 'rgba(124,58,237,0.15)', border: 'rgba(124,58,237,0.3)', text: '#c4b5fd', dot: '#7c3aed' },
  { bg: 'rgba(37,99,235,0.15)', border: 'rgba(37,99,235,0.3)', text: '#93c5fd', dot: '#2563eb' },
  { bg: 'rgba(5,150,105,0.15)', border: 'rgba(5,150,105,0.3)', text: '#6ee7b7', dot: '#059669' },
  { bg: 'rgba(217,119,6,0.15)', border: 'rgba(217,119,6,0.3)', text: '#fcd34d', dot: '#d97706' },
  { bg: 'rgba(219,39,119,0.15)', border: 'rgba(219,39,119,0.3)', text: '#f9a8d4', dot: '#db2777' },
  { bg: 'rgba(8,145,178,0.15)', border: 'rgba(8,145,178,0.3)', text: '#67e8f9', dot: '#0891b2' },
]

function getPalette(name) {
  let hash = 0
  for (let i = 0; i < name.length; i++) hash = name.charCodeAt(i) + ((hash << 5) - hash)
  return PALETTE[Math.abs(hash) % PALETTE.length]
}

export default function ExpenseList({ expenses, onEdit, onDelete }) {
  if (expenses.length === 0) {
    return (
      <div className="rounded-2xl p-16 text-center" style={{ background: 'rgba(255,255,255,0.03)', border: '1px dashed rgba(255,255,255,0.1)' }}>
        <div className="text-5xl mb-4">💸</div>
        <p className="text-white font-medium mb-1">No expenses yet</p>
        <p className="text-sm" style={{ color: 'rgba(255,255,255,0.4)' }}>Click "+ Add Expense" to record your first one</p>
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
        const palette = getPalette(category)
        const total = items.reduce((s, e) => s + e.amount, 0)

        return (
          <div key={category} className="rounded-2xl overflow-hidden" style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}>

            {/* Category header */}
            <div className="flex items-center justify-between px-5 py-3" style={{ background: 'rgba(255,255,255,0.03)', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
              <div className="flex items-center gap-2">
                <div className="w-2 h-2 rounded-full" style={{ background: palette.dot }} />
                <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full" style={{ background: palette.bg, border: `1px solid ${palette.border}`, color: palette.text }}>
                  {category}
                </span>
              </div>
              <span className="text-sm font-bold text-white">₹{total.toLocaleString()}</span>
            </div>

            {/* Expense rows */}
            <div>
              {items.map((exp, idx) => (
                <div
                  key={exp.id}
                  className="flex items-center px-5 py-3.5 group transition-all"
                  style={{
                    borderBottom: idx < items.length - 1 ? '1px solid rgba(255,255,255,0.04)' : 'none',
                  }}
                >
                  {/* Icon */}
                  <div className="w-9 h-9 rounded-xl flex items-center justify-center mr-3 flex-shrink-0 text-sm" style={{ background: palette.bg }}>
                    💳
                  </div>

                  {/* Title & notes */}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-white truncate">{exp.title}</p>
                    <p className="text-xs mt-0.5 truncate" style={{ color: 'rgba(255,255,255,0.4)' }}>
                      {exp.notes || exp.spent_on}
                    </p>
                  </div>

                  {/* Amount & date */}
                  <div className="text-right ml-4 mr-3">
                    <p className="text-sm font-bold text-white">₹{exp.amount.toLocaleString()}</p>
                    <p className="text-xs mt-0.5" style={{ color: 'rgba(255,255,255,0.35)' }}>{exp.spent_on}</p>
                  </div>

                  {/* Actions */}
                  <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    <button
                      onClick={() => onEdit(exp)}
                      className="w-8 h-8 rounded-lg flex items-center justify-center transition-all"
                      style={{ background: 'rgba(124,58,237,0.15)', color: '#c4b5fd' }}
                      title="Edit"
                    >
                      <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                      </svg>
                    </button>
                    <button
                      onClick={() => onDelete(exp)}
                      className="w-8 h-8 rounded-lg flex items-center justify-center transition-all"
                      style={{ background: 'rgba(220,38,38,0.15)', color: '#fca5a5' }}
                      title="Delete"
                    >
                      <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
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
