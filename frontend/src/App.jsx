import { useState, useEffect, useCallback } from 'react'
import { api } from './api'
import Dashboard from './components/Dashboard'
import ExpenseList from './components/ExpenseList'
import ExpenseModal from './components/ExpenseModal'
import CategoryModal from './components/CategoryModal'

export default function App() {
  const now = new Date()
  const [year, setYear] = useState(now.getFullYear())
  const [month, setMonth] = useState(now.getMonth() + 1)

  const [expenses, setExpenses] = useState([])
  const [categories, setCategories] = useState([])
  const [report, setReport] = useState(null)
  const [loading, setLoading] = useState(true)

  const [showExpenseModal, setShowExpenseModal] = useState(false)
  const [showCategoryModal, setShowCategoryModal] = useState(false)
  const [editingExpense, setEditingExpense] = useState(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [cats, exps, rep] = await Promise.all([
        api.getCategories(),
        api.getExpenses({ limit: 200 }),
        api.getMonthlyReport(year, month),
      ])
      setCategories(cats)
      setExpenses(exps)
      setReport(rep)
    } catch (e) {
      console.error(e)
    } finally {
      setLoading(false)
    }
  }, [year, month])

  useEffect(() => { load() }, [load])

  function openAdd() { setEditingExpense(null); setShowExpenseModal(true) }
  function openEdit(exp) { setEditingExpense(exp); setShowExpenseModal(true) }

  async function saveExpense(data) {
    if (editingExpense) {
      await api.updateExpense(editingExpense.id, data)
    } else {
      await api.createExpense(data)
    }
    load()
  }

  async function deleteExpense(exp) {
    if (!confirm(`Delete "${exp.title}"?`)) return
    await api.deleteExpense(exp.id)
    load()
  }

  async function saveCategory(name) {
    await api.createCategory(name)
    load()
  }

  async function deleteCategory(cat) {
    if (!confirm(`Delete "${cat.name}"? All its expenses will also be deleted.`)) return
    await api.deleteCategory(cat.id)
    load()
  }

  const monthName = new Date(year, month - 1).toLocaleString('default', { month: 'long', year: 'numeric' })

  function prevMonth() {
    const d = new Date(year, month - 2)
    setYear(d.getFullYear())
    setMonth(d.getMonth() + 1)
  }

  function nextMonth() {
    const d = new Date(year, month)
    setYear(d.getFullYear())
    setMonth(d.getMonth() + 1)
  }

  return (
    <div className="min-h-screen" style={{ background: 'linear-gradient(135deg, #0f0f1a 0%, #1a1025 50%, #0f1a1a 100%)' }}>

      {/* Header */}
      <header className="border-b sticky top-0 z-40 backdrop-blur-md" style={{ borderColor: 'rgba(255,255,255,0.08)', background: 'rgba(15,15,26,0.85)' }}>
        <div className="max-w-5xl mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl flex items-center justify-center text-lg" style={{ background: 'linear-gradient(135deg, #7c3aed, #a855f7)' }}>
              💰
            </div>
            <div>
              <h1 className="text-base font-bold text-white leading-none">Expense Tracker</h1>
              <p className="text-xs mt-0.5" style={{ color: 'rgba(255,255,255,0.4)' }}>Personal Finance</p>
            </div>
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => setShowCategoryModal(true)}
              className="text-sm px-3 py-2 rounded-xl font-medium transition-all"
              style={{ background: 'rgba(255,255,255,0.06)', color: 'rgba(255,255,255,0.7)', border: '1px solid rgba(255,255,255,0.1)' }}
            >
              + Category
            </button>
            <button
              onClick={openAdd}
              className="text-sm px-4 py-2 rounded-xl font-medium transition-all text-white"
              style={{ background: 'linear-gradient(135deg, #7c3aed, #a855f7)' }}
            >
              + Add Expense
            </button>
          </div>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-4 py-8">

        {/* Month Navigator */}
        <div className="flex items-center justify-between mb-8">
          <button onClick={prevMonth} className="w-9 h-9 rounded-xl flex items-center justify-center transition-all" style={{ background: 'rgba(255,255,255,0.06)', color: 'rgba(255,255,255,0.6)' }}>
            ←
          </button>
          <div className="text-center">
            <h2 className="text-xl font-bold text-white">{monthName}</h2>
            <p className="text-xs mt-0.5" style={{ color: 'rgba(255,255,255,0.4)' }}>
              {loading ? 'Loading...' : `${report?.expense_count ?? 0} transactions`}
            </p>
          </div>
          <button onClick={nextMonth} className="w-9 h-9 rounded-xl flex items-center justify-center transition-all" style={{ background: 'rgba(255,255,255,0.06)', color: 'rgba(255,255,255,0.6)' }}>
            →
          </button>
        </div>

        {loading ? (
          <div className="flex flex-col items-center justify-center py-32 gap-4">
            <div className="w-10 h-10 rounded-full border-2 border-t-transparent animate-spin" style={{ borderColor: '#7c3aed', borderTopColor: 'transparent' }} />
            <p style={{ color: 'rgba(255,255,255,0.4)' }}>Loading your expenses...</p>
          </div>
        ) : (
          <>
            <Dashboard report={report} />

            {/* Categories */}
            {categories.length > 0 && (
              <div className="flex flex-wrap gap-2 mb-6">
                {categories.map((cat) => (
                  <div key={cat.id} className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm transition-all group" style={{ background: 'rgba(124,58,237,0.15)', border: '1px solid rgba(124,58,237,0.3)', color: '#c4b5fd' }}>
                    <span className="font-medium">{cat.name}</span>
                    <button onClick={() => deleteCategory(cat)} className="opacity-0 group-hover:opacity-100 transition-opacity ml-0.5 hover:text-red-400 text-xs leading-none">×</button>
                  </div>
                ))}
              </div>
            )}

            {/* Expenses header */}
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-white">All Transactions</h3>
              <span className="text-sm px-2.5 py-1 rounded-lg" style={{ background: 'rgba(255,255,255,0.06)', color: 'rgba(255,255,255,0.5)' }}>
                {expenses.length} total
              </span>
            </div>

            <ExpenseList expenses={expenses} onEdit={openEdit} onDelete={deleteExpense} />
          </>
        )}
      </main>

      {showExpenseModal && (
        <ExpenseModal
          expense={editingExpense}
          categories={categories}
          onSave={saveExpense}
          onClose={() => setShowExpenseModal(false)}
        />
      )}

      {showCategoryModal && (
        <CategoryModal
          onSave={saveCategory}
          onClose={() => setShowCategoryModal(false)}
        />
      )}
    </div>
  )
}
