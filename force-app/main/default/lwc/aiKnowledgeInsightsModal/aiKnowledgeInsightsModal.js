import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getPerformanceHighlights from '@salesforce/apex/AccountAiInsightsController.getPerformanceHighlights';
import getAccountInsightsNarrative from '@salesforce/apex/AccountAiInsightsController.getAccountInsightsNarrative';
import getRecommendedActions from '@salesforce/apex/AccountAiInsightsController.getRecommendedActions';
import { convertMarkdownToHtml } from 'c/markdownUtils';

export default class AiKnowledgeInsightsModal extends LightningModal {
    @api recordId;

    highlights;
    isLoadingHighlights = true;
    highlightsError;

    insightsHtml;
    isLoadingInsights = true;
    insightsError;

    recommendedActions = [];
    isLoadingActions = true;
    actionsError;

    activeFlow;

    get flowInputVariables() {
        return [{ name: 'account', type: 'SObject', value: { Id: this.recordId } }];
    }

    get hasNoRecommendedActions() {
        return !this.actionsError && this.recommendedActions.length === 0;
    }

    connectedCallback() {
        this.loadHighlights();
        this.loadInsights();
        this.loadRecommendedActions();
    }

    loadHighlights() {
        getPerformanceHighlights({ accountId: this.recordId })
            .then((data) => {
                this.highlights = data;
                this.highlightsError = undefined;
            })
            .catch((error) => {
                this.highlightsError = error?.body?.message || 'Unable to load performance data.';
            })
            .finally(() => {
                this.isLoadingHighlights = false;
            });
    }

    loadInsights() {
        getAccountInsightsNarrative({ accountId: this.recordId })
            .then((markdown) => {
                this.insightsHtml = convertMarkdownToHtml(markdown);
                this.insightsError = undefined;
            })
            .catch((error) => {
                this.insightsError = error?.body?.message || 'Unable to generate insights.';
            })
            .finally(() => {
                this.isLoadingInsights = false;
            });
    }

    loadRecommendedActions() {
        getRecommendedActions({ accountId: this.recordId })
            .then((data) => {
                this.recommendedActions = data;
                this.actionsError = undefined;
            })
            .catch((error) => {
                this.actionsError = error?.body?.message || 'Unable to load recommended actions.';
            })
            .finally(() => {
                this.isLoadingActions = false;
            });
    }

    handleActionClick(event) {
        const actionKey = event.currentTarget.dataset.actionKey;
        this.activeFlow = this.recommendedActions.find((action) => action.actionKey === actionKey);
    }

    handleBackToActions() {
        this.activeFlow = undefined;
    }

    handleFlowStatusChange(event) {
        if (event.detail.status === 'FINISHED' || event.detail.status === 'FINISHED_SCREEN') {
            this.activeFlow = undefined;
        }
    }

    handleClose() {
        this.close();
    }
}
