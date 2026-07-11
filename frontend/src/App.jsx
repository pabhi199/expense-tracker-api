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
    if (!confirm(`Delete category "${cat.name}"? All its expenses will also be deleted.`)) return
    await api.deleteCategory(cat.id)
    load()
  }

  const monthName = new Date(year, month - 1).toLocaleString('default', { month: 'long', year: 'numeric' })

  return (
    <div className="min-h-screen bg-slate-100">
      {/* Header */}
      <header className="bg-white border-b border-slate-200 shadow-sm">
        <div className="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-2xl">💰</span>
            <h1 className="text-xl font-bold text-slate-800">Expense Tracker</h1>
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => setShowCategoryModal(true)}
              className="text-sm border border-slate-200 text-slate-600 px-3 py-1.5 rounded-lg hover:bg-slate-50 font-medium"
            >
              + Category
            </button>
            <button
              onClick={openAdd}
              className="text-sm bg-violet-600 text-white px-4 py-1.5 rounded-lg hover:bg-violet-700 font-medium"
            >
              + Add Expense
            </button>
          </div>
        </div>
      </header>

      <main className="max-w-4xl mx-auto px-4 py-6">
        {/* Month Selector */}
        <div className="flex items-center gap-3 mb-6">
          <button
            onClick={() => { const d = new Date(year, month - 2); setYear(d.getFullYear()); setMonth(d.getMonth() + 1) }}
            className="p-2 rounded-lg hover:bg-white text-slate-500 hover:text-slate-800"
          >
            &#8592;
          </button>
          <h2 className="text-lg font-semibold text-slate-700 w-44 text-center">{monthName}</h2>
          <button
            onClick={() => { const d = new Date(year, month); setYear(d.getFullYear()); setMonth(d.getMonth() + 1) }}
            className="p-2 rounded-lg hover:bg-white text-slate-500 hover:text-slate-800"
          >
            &#8594;
          </button>
        </div>

        {loading ? (
          <div className="text-center py-20 text-slate-400">Loading...</div>
        ) : (
          <>
            <Dashboard report={report} />

            {/* Categories bar */}
            {categories.length > 0 && (
              <div className="flex flex-wrap gap-2 mb-5">
                {categories.map((cat) => (
                  <div key={cat.id} className="flex items-center gap-1 bg-white border border-slate-200 rounded-full px-3 py-1 text-sm">
                    <span className="text-slate-700 font-medium">{cat.name}</span>
                    <button
                      onClick={() => deleteCategory(cat)}
                      className="text-slate-300 hover:text-red-500 ml-1 leading-none"
                      title="Delete category"
                    >
                      &times;
                    </button>
                  </div>
                ))}
              </div>
            )}

            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-slate-700">All Expenses</h3>
              <span className="text-sm text-slate-400">{expenses.length} items</span>
            </div>

            <ExpenseList
              expenses={expenses}
              onEdit={openEdit}
              onDelete={deleteExpense}
            />
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
