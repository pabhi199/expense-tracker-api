"""Pydantic schemas — request validation and response shaping."""
from datetime import date, datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


# ---------- Category ----------
class CategoryBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=50, examples=["Food"])


class CategoryCreate(CategoryBase):
    pass


class CategoryOut(CategoryBase):
    model_config = ConfigDict(from_attributes=True)
    id: int


# ---------- Expense ----------
class ExpenseBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=100, examples=["Lunch at cafe"])
    amount: float = Field(..., gt=0, examples=[249.50])
    spent_on: date = Field(default_factory=date.today)
    notes: Optional[str] = Field(None, max_length=255)
    category_id: int


class ExpenseCreate(ExpenseBase):
    pass


class ExpenseUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=100)
    amount: Optional[float] = Field(None, gt=0)
    spent_on: Optional[date] = None
    notes: Optional[str] = Field(None, max_length=255)
    category_id: Optional[int] = None


class ExpenseOut(ExpenseBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime
    category: CategoryOut


# ---------- Reports ----------
class CategorySummary(BaseModel):
    category: str
    total: float


class MonthlySummary(BaseModel):
    year: int
    month: int
    total_spent: float
    expense_count: int
    by_category: List[CategorySummary]
