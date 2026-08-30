import { LightningElement, api } from 'lwc';
import AiKnowledgeInsightsModal from 'c/aiKnowledgeInsightsModal';

export default class AiKnowledgeInsightsButton extends LightningElement {
    @api recordId;

    async handleOpenModal() {
        await AiKnowledgeInsightsModal.open({
            size: 'full',
            label: 'AI Knowledge & Insights',
            recordId: this.recordId
        });
    }
}
