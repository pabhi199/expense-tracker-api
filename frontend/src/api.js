const BASE = import.meta.env.VITE_API_URL || '/api'

async function request(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }))
    throw new Error(err.detail || 'Request failed')
  }
  if (res.status === 204) return null
  return res.json()
}

export const api = {
  getCategories: () => request('GET', '/categories'),
  createCategory: (name) => request('POST', '/categories', { name }),
  deleteCategory: (id) => request('DELETE', `/categories/${id}`),

  getExpenses: (params = {}) => {
    const q = new URLSearchParams()
    Object.entries(params).forEach(([k, v]) => v != null && q.set(k, v))
    return request('GET', `/expenses?${q}`)
  },
  createExpense: (data) => request('POST', '/expenses', data),
  updateExpense: (id, data) => request('PATCH', `/expenses/${id}`, data),
  deleteExpense: (id) => request('DELETE', `/expenses/${id}`),

  getMonthlyReport: (year, month) => request('GET', `/expenses/report/${year}/${month}`),
}
