"""CRUD layer — all database operations live here, keeping routers thin."""
from datetime import date
from typing import List, Optional

from sqlalchemy import extract, func
from sqlalchemy.orm import Session

from . import models, schemas


# ---------- Category ----------
def get_category(db: Session, category_id: int) -> Optional[models.Category]:
    return db.get(models.Category, category_id)


def get_category_by_name(db: Session, name: str) -> Optional[models.Category]:
    return db.query(models.Category).filter(models.Category.name == name).first()


def list_categories(db: Session) -> List[models.Category]:
    return db.query(models.Category).order_by(models.Category.name).all()


def create_category(db: Session, data: schemas.CategoryCreate) -> models.Category:
    category = models.Category(name=data.name)
    db.add(category)
    db.commit()
    db.refresh(category)
    return category


def delete_category(db: Session, category: models.Category) -> None:
    db.delete(category)
    db.commit()


# ---------- Expense ----------
def get_expense(db: Session, expense_id: int) -> Optional[models.Expense]:
    return db.get(models.Expense, expense_id)


def list_expenses(
    db: Session,
    skip: int = 0,
    limit: int = 50,
    category_id: Optional[int] = None,
    start: Optional[date] = None,
    end: Optional[date] = None,
) -> List[models.Expense]:
    query = db.query(models.Expense)
    if category_id is not None:
        query = query.filter(models.Expense.category_id == category_id)
    if start is not None:
        query = query.filter(models.Expense.spent_on >= start)
    if end is not None:
        query = query.filter(models.Expense.spent_on <= end)
    return (
        query.order_by(models.Expense.spent_on.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )


def create_expense(db: Session, data: schemas.ExpenseCreate) -> models.Expense:
    expense = models.Expense(**data.model_dump())
    db.add(expense)
    db.commit()
    db.refresh(expense)
    return expense


def update_expense(
    db: Session, expense: models.Expense, data: schemas.ExpenseUpdate
) -> models.Expense:
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(expense, field, value)
    db.commit()
    db.refresh(expense)
    return expense


def delete_expense(db: Session, expense: models.Expense) -> None:
    db.delete(expense)
    db.commit()


# ---------- Reports ----------
def monthly_summary(db: Session, year: int, month: int) -> schemas.MonthlySummary:
    base = db.query(models.Expense).filter(
        extract("year", models.Expense.spent_on) == year,
        extract("month", models.Expense.spent_on) == month,
    )
    total = base.with_entities(func.coalesce(func.sum(models.Expense.amount), 0.0)).scalar()
    count = base.count()

    rows = (
        db.query(models.Category.name, func.sum(models.Expense.amount))
        .join(models.Expense)
        .filter(
            extract("year", models.Expense.spent_on) == year,
            extract("month", models.Expense.spent_on) == month,
        )
        .group_by(models.Category.name)
        .all()
    )
    by_category = [
        schemas.CategorySummary(category=name, total=round(t, 2)) for name, t in rows
    ]
    return schemas.MonthlySummary(
        year=year,
        month=month,
        total_spent=round(total, 2),
        expense_count=count,
        by_category=by_category,
    )
