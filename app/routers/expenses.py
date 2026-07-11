"""Expense endpoints, including the monthly report."""
from datetime import date
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from .. import crud, schemas
from ..database import get_db

router = APIRouter(prefix="/expenses", tags=["expenses"])


@router.get("", response_model=List[schemas.ExpenseOut])
def list_expenses(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    category_id: Optional[int] = None,
    start: Optional[date] = None,
    end: Optional[date] = None,
    db: Session = Depends(get_db),
):
    return crud.list_expenses(db, skip, limit, category_id, start, end)


@router.post("", response_model=schemas.ExpenseOut, status_code=status.HTTP_201_CREATED)
def create_expense(payload: schemas.ExpenseCreate, db: Session = Depends(get_db)):
    if not crud.get_category(db, payload.category_id):
        raise HTTPException(status_code=404, detail="Category not found")
    return crud.create_expense(db, payload)


@router.get("/report/{year}/{month}", response_model=schemas.MonthlySummary)
def monthly_report(year: int, month: int, db: Session = Depends(get_db)):
    if not 1 <= month <= 12:
        raise HTTPException(status_code=422, detail="Month must be 1-12")
    return crud.monthly_summary(db, year, month)


@router.get("/{expense_id}", response_model=schemas.ExpenseOut)
def get_expense(expense_id: int, db: Session = Depends(get_db)):
    expense = crud.get_expense(db, expense_id)
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found")
    return expense


@router.patch("/{expense_id}", response_model=schemas.ExpenseOut)
def update_expense(
    expense_id: int, payload: schemas.ExpenseUpdate, db: Session = Depends(get_db)
):
    expense = crud.get_expense(db, expense_id)
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found")
    if payload.category_id is not None and not crud.get_category(db, payload.category_id):
        raise HTTPException(status_code=404, detail="Category not found")
    return crud.update_expense(db, expense, payload)


@router.delete("/{expense_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_expense(expense_id: int, db: Session = Depends(get_db)):
    expense = crud.get_expense(db, expense_id)
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found")
    crud.delete_expense(db, expense)
