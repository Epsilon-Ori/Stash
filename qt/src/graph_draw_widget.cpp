/*
 * Stash:  A Personal Finance app (Qt UI).
 * Copyright (C) 2020 Peter Pearson
 * You can view the complete license in the Licence.txt file in the root
 * of the source tree.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 *
 */

#include "graph_draw_widget.h"

#include <cmath>

#include <QDate>
#include <QPainter>
#include <QMouseEvent>

#include "stash_window.h"
#include "ui_currency_formatter.h"

GraphDrawWidget::GraphDrawWidget(StashWindow* pStashWindow, QWidget* pParent) : QWidget(pParent), m_pStashWindow(pStashWindow)
{
	// TODO: static instead?
	
	m_aPieColours.emplace_back(Qt::green);
	m_aPieColours.emplace_back(Qt::red);
	m_aPieColours.emplace_back(Qt::blue);
	m_aPieColours.emplace_back(QColor(125, 125, 0));
	m_aPieColours.emplace_back(Qt::darkGray);
	m_aPieColours.emplace_back(Qt::yellow);
	
	for (QColor& col : m_aPieColours)
	{
		col = col.lighter(150);

		QColor areaColour = col;
		areaColour.setAlpha(128);

		m_aAreaColours.emplace_back(areaColour);
	}
	
	m_selectedItemIndex = -1;
}


void GraphDrawWidget::paintEvent(QPaintEvent* event)
{
	// TODO: draw to QPixmap backbuffer instead of doing full draw each time?
	QPainter painter(this);
	
	painter.setPen(Qt::black);
	painter.drawRect(geometry());
	
	if (m_graphType == eGraphPieChart)
	{
		drawPieChart(painter, event);
	}
	else if (m_graphType == eGraphAreaChart)
	{
		drawAreaChart(painter, event);
	}
}

void GraphDrawWidget::setPieChartItems(const std::vector<PieChartItem>& items)
{
	m_graphType = eGraphPieChart;
	
	m_aPieChartItems = items;
	
	m_selectedItemIndex = -1;
	
	update();
	repaint();
}

void GraphDrawWidget::setAreaChartItems(const std::vector<AreaChartItemValues>& dataItems, const std::vector<MonthYear>& dates, fixed maxValue)
{
	m_graphType = eGraphAreaChart;

	m_aAreaChartDataItems = dataItems;
	m_aAreaChartDates.clear();
	// format the dates
	for (const MonthYear& my : dates)
	{
		QDate date(my.getYear(), my.getMonth(), 1);

		QString formattedDate = date.toString("MMM\nyyyy");
		m_aAreaChartDates.emplace_back(formattedDate);
	}

	// work out the longest date
	// for the moment, just hard-code September
	m_longestDate = "September";

	m_maxValue = maxValue;

	m_selectedItemIndex = -1;

	update();
	repaint();
}

void GraphDrawWidget::mouseReleaseEvent(QMouseEvent* event)
{
	if (event->button() != Qt::LeftButton)
		return;

	bool earlyOut = false;

	if (m_graphType == eGraphPieChart)
	{
		if (m_aPieChartItems.empty())
		{
			m_selectedItemIndex = -1;
			update();
			repaint();
			return;
		}

		float smallestExtent = 0.0f;

		if (geometry().height() < geometry().width())
			smallestExtent = geometry().height();
		else
			smallestExtent = geometry().width();

		float mainRadius = (smallestExtent / 2.0f) - 25.0f;

		QPoint centrePoint = geometry().center();

		float deltaX = event->pos().x() - centrePoint.x();
		float deltaY = event->pos().y() - centrePoint.y();

		float hitPosRadius = std::sqrt(deltaY * deltaY + deltaX * deltaX);

		if (hitPosRadius > mainRadius)
		{
			m_selectedItemIndex = -1;
			earlyOut = true;
		}

		if (!earlyOut)
		{
			float angleRads = std::atan2(deltaX, deltaY);
			float angleDegs = angleRads * 57.2958f;

			// compensate for differing start position when drawing (starts at 90 deg (3 o'clock)
			angleDegs -= 90.0f;

			if (angleDegs < 0.0f)
				angleDegs += 360.0f;

			float cumulativeAngle = 0.0f;
			int index = 0;
			for (const PieChartItem& item : m_aPieChartItems)
			{
				float endAngle = cumulativeAngle + item.angle;

				if (angleDegs > cumulativeAngle && angleDegs < endAngle)
				{
					m_selectedItemIndex = index;
					break;
				}

				cumulativeAngle += item.angle;
				index++;
			}
		}
	}
	else if (m_graphType == eGraphAreaChart)
	{
		if (m_aAreaChartDataItems.empty() || m_aAreaChartDataItems[0].values.size() <= 2)
		{
			m_selectedItemIndex = -1;
			update();
			repaint();
			return;
		}
	}

	update();
	repaint();
}

void GraphDrawWidget::drawPieChart(QPainter& painter, QPaintEvent* event)
{
	if (m_aPieChartItems.empty())
		return;
	
	painter.setRenderHint(QPainter::Antialiasing);
	
	float smallestExtent = 0.0f;
	
	if (geometry().height() < geometry().width())
		smallestExtent = geometry().height();
	else
		smallestExtent = geometry().width();
	
	float mainRadius = (smallestExtent / 2.0f) - 25.0f;
	
	QPoint centrePoint = geometry().center();
	// Can't use inline QPoint operations apparently...
	QRect mainRadiusRect(QPoint(centrePoint.rx() - mainRadius, centrePoint.ry() - mainRadius),
						 QPoint(centrePoint.rx() + mainRadius, centrePoint.ry() + mainRadius));
	
	
	// if we don't use float, we get a gap at the end, as we end up missing 9/10 16ths of the circle...
	// TODO: it's still not a perfect fit with this, so something else must also be going on...
	float lastAngleSixteenthsF = 0.0f;
	
	unsigned int colourIndex = 0;
	
	painter.setPen(Qt::darkGray);
	
	// draw the basic wedges
	for (const PieChartItem& item : m_aPieChartItems)
	{
		float thisAngleF = item.angle * 16.0f;
		int thisAngleI = (int)thisAngleF;
		int lastAngleI = (int)lastAngleSixteenthsF;
		
		painter.setBrush(QBrush(m_aPieColours[colourIndex++]));
		if (colourIndex >= m_aPieColours.size())
		{
			colourIndex = 0;
		}
		
		painter.drawPie(mainRadiusRect, lastAngleI, thisAngleI);
		
		lastAngleSixteenthsF += thisAngleF;
	}
	
	// now loop over again, drawing any selection highlights, plus text on top
	
	QFont newFont = font();
	newFont.setPointSize(9);
	setFont(newFont);

	QFontMetrics metrics(font());
	
	int textExtentHeight = metrics.height();
	
	painter.setPen(Qt::black);
	
	lastAngleSixteenthsF = 0.0f;
	float lastAngle = 0.0f;
	int itemIndex = 0;
	for (const PieChartItem& item : m_aPieChartItems)
	{
		float thisAngleF = item.angle * 16.0f;
		int thisAngleI = (int)thisAngleF;
		int lastAngleI = (int)lastAngleSixteenthsF;

		if (m_selectedItemIndex != -1 && m_selectedItemIndex == itemIndex++)
		{
			// configure thick selection line for outline, and no brush for no fill colour
			QPen selectionPen(Qt::white, 4, Qt::DashLine, Qt::RoundCap, Qt::RoundJoin);
			painter.setPen(selectionPen);
			painter.setBrush(Qt::NoBrush);
			painter.drawPie(mainRadiusRect, lastAngleI, thisAngleI);

			painter.setPen(Qt::black);
		}

		float midPointAngle = (((lastAngle + item.angle) - lastAngle) / 2.0) + lastAngle;
				
		float midPointRads = midPointAngle * 0.017453f;
		
		float wedgeEdgeCentrePosX = std::cos(midPointRads);
		float wedgeEdgeCentrePosY = std::sin(midPointRads);
		
		QString fullText;
		fullText.sprintf("%s  %s",	item.title.c_str(), item.amount.toStdString().c_str());		
		
		int textExtentWidth = metrics.width(fullText);
				
		float fTextStartPosX = centrePoint.rx() + (wedgeEdgeCentrePosX * mainRadius);
		float fTextStartPosY = centrePoint.ry() - (wedgeEdgeCentrePosY * mainRadius);
		
		fTextStartPosX -= ((float)textExtentWidth / 2.0f);
		fTextStartPosY += ((float)textExtentHeight / 2.0f);
		
		// check to see if we're going to fall off the end - if so, move the text
		// left a bit
		/*
		if ((dStartX + extent.width) >= bounds.size.width)
		{
			dStartX -= (dStartX + extent.width) - bounds.size.width;
		}
		else if (dStartX < bounds.origin.x)
		{
			dStartX = 0.0;
		}
		*/
		
		painter.drawText(QPointF(fTextStartPosX, fTextStartPosY), fullText);
		
		lastAngle += item.angle;
		lastAngleSixteenthsF += thisAngleF;
	}
}

void GraphDrawWidget::drawAreaChart(QPainter& painter, QPaintEvent* event)
{
	if (m_aAreaChartDataItems.empty() || m_aAreaChartDataItems[0].values.size() <= 2)
		return;

	QFontMetrics metrics(font());

	UICurrencyFormatter* currencyFormatter = m_pStashWindow->getCurrencyFormatter();
	QString maxValueString = currencyFormatter->formatCurrencyAmount(m_maxValue);

	float leftMargin = 30.0f + metrics.width(maxValueString);
	int bottomMargin = (metrics.height() * 2) + 20;

	painter.setRenderHint(QPainter::Antialiasing);

	unsigned int numXValues = m_aAreaChartDataItems[0].values.size();

	QRect plotArea = geometry();
	plotArea.adjust(leftMargin, 20, -20, -bottomMargin);

	painter.drawRect(plotArea);

	// try and generate a "nice" number which divides easily
	double ceilMaxValue = std::ceil(std::ceil(m_maxValue.ToDouble() / 10.0) * 10.0);

	float xIncrement = (float)plotArea.width() / (float)(numXValues - 1);
	float YScale = (float)plotArea.height() / (float)ceilMaxValue;

	painter.setPen(Qt::darkGray);

	int dateLabelAlternating = 1;

	// work out how many X-axis labels can fit into the space available
	if (!m_longestDate.empty())
	{
		float dateTextWidth = metrics.width(m_longestDate.c_str());
		// slight margin so that we ensure that labels don't touch
		dateTextWidth += 4.0f;

		if (dateTextWidth >= xIncrement)
			dateLabelAlternating = 2;

		if (dateTextWidth >= xIncrement * 2.0f)
			dateLabelAlternating = 3;
	}


	QRect yAxisLabelRect(0, plotArea.bottom() + 10, 40, 30);
	// draw x gridlines
	for (unsigned int i = 0; i < numXValues; i++)
	{
		float xPos = plotArea.left() + (xIncrement * i);

		painter.setPen(Qt::darkGray);

		painter.drawLine(QPointF(xPos, plotArea.bottom()), QPointF(xPos, plotArea.top()));

		if (i == 0 || i % dateLabelAlternating == 0)
		{
			const QString& dateStr = m_aAreaChartDates[i];
			float textExtent = metrics.width(dateStr);

			painter.setPen(Qt::black);

			yAxisLabelRect.setLeft(xPos - (textExtent / 2.0f));
			// if we're the last label, we're probably going to be off the edge slightly, so push the
			// extent back a bit
			if (i == (numXValues - 1))
			{
				yAxisLabelRect.setLeft(yAxisLabelRect.left() - 10);
			}

			yAxisLabelRect.setRight(xPos + (textExtent / 2.0f));
			painter.drawText(yAxisLabelRect, Qt::AlignCenter, dateStr);
		}
	}

	// draw Y gridlines and labels

	// work out number of y gridlines
	unsigned int numYGrids = 0.4f * std::sqrt((float)plotArea.height());
	int nRem = numYGrids % 2;
	// enforce even numbers so that the scale will look nicer
	numYGrids += nRem;

	float YInc = ceilMaxValue / numYGrids;

	numYGrids++;

	int textHeight = metrics.height();

	for (int i = 0; i < numYGrids; i++)
	{
		float thisYValue = plotArea.top() + ((YInc * i) * YScale);

		fixed lineValue = (double)ceilMaxValue - (double)(YInc * i);
		QString lineValueString = currencyFormatter->formatCurrencyAmount(lineValue);

		painter.setPen(Qt::darkGray);

		painter.drawLine(QPointF(plotArea.left(), thisYValue), QPointF(plotArea.right(), thisYValue));

		painter.setPen(Qt::black);

		painter.drawText(QPoint(20, thisYValue + (textHeight / 2)), lineValueString);
	}

	std::vector<double> baseLineValues(0.0);
	baseLineValues.resize(numXValues);

	unsigned int colourIndex = 0;

	painter.setPen(Qt::black);

	for (const AreaChartItemValues& item : m_aAreaChartDataItems)
	{
		QPolygonF itemShape;

		// draw baseline values anti-clockwise (from left hand side)
		for (unsigned int i = 0; i < numXValues; i++)
		{
			float xPos = plotArea.left() + (xIncrement * i);

			float yVal = baseLineValues[i] * YScale;

			// flip y origin
			yVal = plotArea.height() - yVal;
			yVal += plotArea.top();

			itemShape.append(QPointF(xPos, yVal));
		}

		// then add new values, and add points right-to-left to close the shape

		for (unsigned int i = 0; i < numXValues; i++)
		{
			unsigned int inverseIndex = (numXValues - 1) - i;
			float xPos = plotArea.left() + (xIncrement * inverseIndex);

			// add new data value to baseline value
			baseLineValues[inverseIndex] += item.values[inverseIndex];

			float yVal = baseLineValues[inverseIndex] * YScale;

			// flip y origin
			yVal = plotArea.height() - yVal;
			yVal += plotArea.top();

			itemShape.append(QPointF(xPos, yVal));
		}

		painter.setBrush(QBrush(m_aAreaColours[colourIndex++]));
		if (colourIndex >= m_aAreaColours.size())
		{
			colourIndex = 0;
		}

		painter.drawPolygon(itemShape, Qt::WindingFill);
	}
}